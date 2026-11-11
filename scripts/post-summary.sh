#!/usr/bin/env bash
# Writes the full report: the report of the agent plus the usage of the run and the skipped PRs,
# to the GitHub job summary (or to stdout when run locally).
#
# Env: OUTPUT_DIR (default: output), CONTEXT_DIR (default: context), SCOPE, MODEL, GITHUB_STEP_SUMMARY,
#      JIRA_BASE_URL (optional, turns ticket keys into links), LANGUAGE (Dutch, or English by default)

set -euo pipefail

OUTPUT="${OUTPUT_DIR:-output}"
CONTEXT="${CONTEXT_DIR:-context}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"

case "$(tr '[:upper:]' '[:lower:]' <<< "${LANGUAGE:-English}")" in
  dutch | nederlands | nl*) HEADERS='| Ticket | Verdict | Toelichting |' ;;
  *) HEADERS='| Ticket | Verdict | Note |' ;;
esac

# The table of tickets, built from results.json instead of written by the agent, so every key links to
# Jira and shows the ticket's title. Keys and verdicts use non-breaking hyphens so they never wrap.
tickets_table() {
  local titles="{}"
  [[ -f "$CONTEXT/jira-titles.json" ]] && titles=$(cat "$CONTEXT/jira-titles.json")
  jq -r --arg jira "${JIRA_BASE_URL:-}" --arg repo_url "$REPO_URL" --arg headers "$HEADERS" \
    --argjson titles "$titles" '
    def cell: tostring | gsub("[\r\n]+"; " ") | gsub("\\|"; "\\|");
    def nowrap: gsub("-"; "\u2011");
    def name:
      if (.key | type) == "string" and .key != "" then
        (if $jira == "" then (.key | nowrap) else "[\(.key | nowrap)](\($jira)/browse/\(.key))" end)
      elif ((.prs // []) | length) > 0 then "[#\(.prs[0])](\($repo_url)/pull/\(.prs[0]))"
      else "?" end;
    def title: ($titles[.key // ""] // .title // "") | cell;
    def icon: {"fail": "🐞", "needs-human": "👀", "pass": "✅", "not-testable": "➖"}[.verdict] // "❓";
    def rank: {"fail": 0, "needs-human": 1, "pass": 2}[.verdict] // 3;
    [.tickets[]? | objects] | sort_by(rank)
    | if length == 0 then empty else
        $headers, "|---|---|---|",
        (.[] | "| \(name) | \(icon) \(.verdict // "?" | cell | nowrap) | "
          + (title | if . == "" then "" else "**\(.)**<br>" end) + (.summary_line // "" | cell) + " |")
      end' "$OUTPUT/results.json" 2> /dev/null || true
}

{
  table=""
  [[ -f "$OUTPUT/results.json" ]] && table=$(tickets_table)
  if [[ -f "$OUTPUT/report.md" ]]; then
    if grep -q '^<!-- tickets -->$' "$OUTPUT/report.md"; then
      while IFS= read -r line; do
        if [[ "$line" == "<!-- tickets -->" ]]; then echo "$table"; else echo "$line"; fi
      done < "$OUTPUT/report.md"
    else
      # An agent that forgot the placeholder still gets the table, above its report.
      [[ -n "$table" ]] && printf '%s\n\n' "$table"
      cat "$OUTPUT/report.md"
    fi
  else
    echo "## No QA report"
    echo
    echo "The agent did not write a report; see the run log."
  fi
  echo
  echo "---"
  echo
  echo "### Run details"
  echo
  echo "- Scope: \`${SCOPE:-yesterday}\`"
  echo "- Model: \`${MODEL:-unknown}\`"
  if [[ -f "$OUTPUT/copilot-usage.json" ]]; then
    jq -r '"- AI credits: \((.totalNanoAiu // 0) / 1e9 * 100 | round / 100) (100 credits = 1 USD)",
           "- Model calls: \([.modelMetrics[]?.requests.count] | add // 0)"' "$OUTPUT/copilot-usage.json" || true
  fi
  if [[ -f "$OUTPUT/global-teardown-log.txt" ]]; then
    # The script ends with a line like "Closed 4 of 4 test records, 0 left."; otherwise show the last line.
    result=$(grep -iE "closed|removed|deleted|aborted|left" "$OUTPUT/global-teardown-log.txt" | tail -1)
    echo "- Cleanup: ${result:-$(grep -v '^\s*$' "$OUTPUT/global-teardown-log.txt" | tail -1)}"
  fi
  if [[ -f "$CONTEXT/skipped.json" ]] && [[ $(jq length "$CONTEXT/skipped.json") -gt 0 ]]; then
    echo
    echo "<details><summary>$(jq length "$CONTEXT/skipped.json") PRs not tested</summary>"
    echo
    jq -r '.[] | "- [#\(.number)](\(.url)) \(.title): \(.skip_reason)"' "$CONTEXT/skipped.json"
    echo
    echo "</details>"
  fi
} >> "$SUMMARY"
