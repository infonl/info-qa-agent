#!/usr/bin/env bash
# Posts the teammate-style message of the agent to Slack, ending in a link to the full report.
# A run without results still posts a short warning, so a broken run never looks like a quiet day.
#
# Env:
#   SLACK_WEBHOOK_URL   incoming webhook; without it, nothing is posted
#   SLACK_DRY_RUN=true  print the payload instead of posting it
#   JIRA_BASE_URL       optional, turns ticket keys into links
#   JIRA_PROJECT_KEYS   optional, comma separated; limits which keys become links
#   RESULTS             results file (default: output/results.json)
#   LANGUAGE            language of the fixed texts: Dutch, or English (default)
#   GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID (set by Actions)

set -euo pipefail

RESULTS="${RESULTS:-output/results.json}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

case "$(tr '[:upper:]' '[:lower:]' <<< "${LANGUAGE:-English}")" in
  dutch | nederlands | nl*)
    REPORT_LINK="Lees hier mijn volledige rapport"
    NOT_TESTABLE="Niet in de browser te testen"
    MORE="en nog %s"
    FAILED_SHORT="Mijn QA-run is vandaag niet afgerond."
    FAILED_LONG="Mijn QA-run is vandaag niet afgerond, dus ik heb niets te melden. Er ging iets mis aan mijn kant, <%s|het log> heeft de details."
    ;;
  *)
    REPORT_LINK="Read my full report here"
    NOT_TESTABLE="Not testable in the browser"
    MORE="and %s more"
    FAILED_SHORT="My QA run did not finish today."
    FAILED_LONG="My QA run did not finish today, so I have nothing to report. Something went wrong on my side, <%s|the log> has the details."
    ;;
esac
# shellcheck disable=SC2059 # the format string is one of the two fixed texts above
FAILED_LONG=$(printf "$FAILED_LONG" "$RUN_URL")

if [[ -z "${SLACK_WEBHOOK_URL:-}" && "${SLACK_DRY_RUN:-false}" != "true" ]]; then
  echo "No Slack webhook, skipping Slack."
  exit 0
fi

if [[ -n "${JIRA_PROJECT_KEYS:-}" ]]; then
  KEY_RE="\\b($(tr -d ' ' <<< "$JIRA_PROJECT_KEYS" | tr ',' '|'))-[0-9]+\\b"
else
  KEY_RE='\b[A-Z][A-Z0-9]{1,9}-[0-9]+\b'
fi

payload=""
if [[ -f "$RESULTS" ]] && jq -e '.slack_message | type == "string" and length > 0' "$RESULTS" > /dev/null 2>&1; then
  # Any failure here falls back to the warning below, so a broken results file never goes unreported.
  payload=$(jq --arg run "$RUN_URL" --arg jira "${JIRA_BASE_URL:-}" --arg key_re "$KEY_RE" \
    --arg report_link "$REPORT_LINK" --arg not_testable "$NOT_TESTABLE" --arg more "$MORE" \
    --arg repo_url "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}" '
    def escape: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def link_tickets:
      if $jira == "" then . else gsub("(?<key>\($key_re))"; "<\($jira)/browse/\(.key)|\(.key)>") end;
    # A ticket links to Jira; a PR without a ticket links to the PR.
    def name:
      if (.key | type) == "string" and .key != "" then
        (if $jira == "" then .key else "<\($jira)/browse/\(.key)|\(.key)>" end)
      elif ((.prs // []) | length) > 0 then "<\($repo_url)/pull/\(.prs[0])|#\(.prs[0])>"
      else "?" end;
    def title: (.title // "" | tostring | escape) as $t | if ($t | length) > 70 then $t[0:69] + "…" else $t end;
    def icon: {"fail": ":beetle:", "needs-human": ":eyes:", "pass": ":white_check_mark:"}[.verdict] // ":grey_question:";
    def rank: {"fail": 0, "needs-human": 1, "pass": 2}[.verdict] // 3;
    def explanation:
      ((.explanation // "") | tostring) as $e
      | (if ($e | length) > 0 then $e else (.summary_line // "" | tostring) end)
      | escape | link_tickets
      | if length > 1500 then .[0:1499] + "…" else . end;
    # Slack allows 3000 characters per section, so the items are spread over as many sections as needed.
    def sections:
      reduce .[] as $item ([];
        if length == 0 then [$item]
        elif ((.[-1] + "\n\n" + $item) | length) > 2900 then . + [$item]
        else .[:-1] + [.[-1] + "\n\n" + $item] end)
      | map({ type: "section", text: { type: "mrkdwn", text: . } });

    (.slack_message | escape) as $message
    | [.tickets[]? | objects] as $tickets
    | [$tickets[] | select(.verdict != "not-testable")] | sort_by(rank) as $tested
    | ([$tested[:15][] | "\(icon) *\(name)  \(title)*" + (explanation | if . == "" then "" else "\n" + . end)]
       + (if ($tested | length) > 15 then [$more | sub("%s"; "\(($tested | length) - 15)")] else [] end)
       + ([$tickets[] | select(.verdict == "not-testable") | name] | if length > 0 then ["\($not_testable): \(join(", "))"] else [] end)
      ) as $items
    | {
        text: $message,
        # Opening, then every ticket with its explanation, then the link to the full report at the bottom.
        # A link, not a button: a button shows a warning in Slack unless the app has interactivity set up.
        blocks: (
          [ { type: "section", text: { type: "mrkdwn", text: ($message | link_tickets) } } ]
          + ($items | sections)
          + [ { type: "section", text: { type: "mrkdwn", text: "<\($run)|\($report_link)>" } } ]
        )
      }' "$RESULTS") || payload=""
fi
if [[ -z "$payload" ]]; then
  payload=$(jq -n --arg short "$FAILED_SHORT" --arg long "$FAILED_LONG" '{
    text: $short,
    blocks: [ { type: "section", text: { type: "mrkdwn", text: ":warning: \($long)" } } ]
  }')
fi

if [[ "${SLACK_DRY_RUN:-false}" == "true" ]]; then
  echo "$payload"
  exit 0
fi

if curl -sS --fail-with-body -X POST -H "Content-Type: application/json" --data "$payload" "$SLACK_WEBHOOK_URL" > /dev/null; then
  echo "Posted to Slack."
else
  echo "warn: posting to Slack failed" >&2
fi
