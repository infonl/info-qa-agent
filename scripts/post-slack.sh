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
    FAILED_SHORT="Mijn QA-run is vandaag niet afgerond."
    FAILED_LONG="Mijn QA-run is vandaag niet afgerond, dus ik heb niets te melden. Er ging iets mis aan mijn kant, <%s|het log> heeft de details."
    ;;
  *)
    REPORT_LINK="Read my full report here"
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
  payload=$(jq --arg run "$RUN_URL" --arg jira "${JIRA_BASE_URL:-}" --arg key_re "$KEY_RE" --arg report_link "$REPORT_LINK" '
    def escape: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def link_tickets:
      if $jira == "" then . else gsub("(?<key>\($key_re))"; "<\($jira)/browse/\(.key)|\(.key)>") end;
    (.slack_message | escape) as $message
    | {
        text: $message,
        # A link, not a button: a button shows a warning in Slack unless the app has interactivity set up.
        blocks: [
          { type: "section", text: { type: "mrkdwn", text: "\($message | link_tickets) <\($run)|\($report_link)>." } }
        ]
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
