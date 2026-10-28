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
#   GITHUB_SERVER_URL, GITHUB_REPOSITORY, GITHUB_RUN_ID (set by Actions)

set -euo pipefail

RESULTS="${RESULTS:-output/results.json}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

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
  payload=$(jq --arg run "$RUN_URL" --arg jira "${JIRA_BASE_URL:-}" --arg key_re "$KEY_RE" '
    def escape: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def link_tickets:
      if $jira == "" then . else gsub("(?<key>\($key_re))"; "<\($jira)/browse/\(.key)|\(.key)>") end;
    (.slack_message | escape) as $message
    | {
        text: $message,
        # A link, not a button: a button shows a warning in Slack unless the app has interactivity set up.
        blocks: [
          { type: "section", text: { type: "mrkdwn", text: "\($message | link_tickets) <\($run)|Read my full report here>." } }
        ]
      }' "$RESULTS") || payload=""
fi
if [[ -z "$payload" ]]; then
  payload=$(jq -n --arg run "$RUN_URL" '{
    text: "My QA run did not finish today.",
    blocks: [
      { type: "section", text: { type: "mrkdwn",
          text: ":warning: My QA run did not finish today, so I have nothing to report. Something went wrong on my side, <\($run)|the log> has the details." } }
    ]}')
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
