#!/usr/bin/env bash
# Writes the full report: the report of the agent plus the usage of the run and the skipped PRs,
# to the GitHub job summary (or to stdout when run locally).
#
# Env: OUTPUT_DIR (default: output), CONTEXT_DIR (default: context), SCOPE, MODEL, GITHUB_STEP_SUMMARY

set -euo pipefail

OUTPUT="${OUTPUT_DIR:-output}"
CONTEXT="${CONTEXT_DIR:-context}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

{
  if [[ -f "$OUTPUT/report.md" ]]; then
    cat "$OUTPUT/report.md"
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
  if [[ -f "$CONTEXT/skipped.json" ]] && [[ $(jq length "$CONTEXT/skipped.json") -gt 0 ]]; then
    echo
    echo "<details><summary>$(jq length "$CONTEXT/skipped.json") PRs not tested</summary>"
    echo
    jq -r '.[] | "- [#\(.number)](\(.url)) \(.title): \(.skip_reason)"' "$CONTEXT/skipped.json"
    echo
    echo "</details>"
  fi
} >> "$SUMMARY"
