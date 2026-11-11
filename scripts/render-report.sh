#!/usr/bin/env bash
# Puts the table of tickets into the agent's report, in place of its `<!-- tickets -->` line, or above the
# report when that line is missing. The table is built from results.json instead of written by the agent,
# so every key links to Jira and shows the ticket's title. Runs before the upload, so the job summary and
# the downloaded report are the same file.
#
# Env:
#   OUTPUT_DIR      default: output
#   CONTEXT_DIR     default: context; the Jira tickets in it give the titles
#   JIRA_BASE_URL   optional, turns ticket keys into links
#   LANGUAGE        language of the column headers: Dutch, or English (default)
#   QA_PASSWORD, QA_PASSWORD_2   replaced with asterisks before escaping, which the later scrub can't undo
#   GITHUB_SERVER_URL, GITHUB_REPOSITORY (set by Actions)

set -euo pipefail

OUTPUT="${OUTPUT_DIR:-output}"
CONTEXT="${CONTEXT_DIR:-context}"
REPORT="$OUTPUT/report.md"
REPO_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"

[[ -f "$REPORT" && -f "$OUTPUT/results.json" ]] || exit 0

case "$(tr '[:upper:]' '[:lower:]' <<< "${LANGUAGE:-English}")" in
  dutch | nederlands | nl*) HEADERS='| Ticket | Verdict | Toelichting |' ;;
  *) HEADERS='| Ticket | Verdict | Note |' ;;
esac

titles=$(find "$CONTEXT/jira" -name '*.json' -exec cat {} + 2> /dev/null \
  | jq -s 'map({(.key): .summary}) | add // {}' 2> /dev/null) || titles='{}'
[[ -n "$titles" ]] || titles='{}'

# Keys and verdicts get non-breaking hyphens so they never wrap; text is escaped, so a title such as
# "Fix <input> validation" shows as text and a | doesn't split the cell.
table=$(jq -r --arg jira "${JIRA_BASE_URL:-}" --arg repo_url "$REPO_URL" --arg headers "$HEADERS" \
  --argjson titles "$titles" '
  def redact: reduce ([$ENV.QA_PASSWORD, $ENV.QA_PASSWORD_2][] | select(type == "string" and length >= 4)) as $s
    (.; split($s) | join($s | gsub("."; "*")));
  # Passwords go before anything is escaped: an escaped password no longer matches the scrub.
  ($titles | map_values(tostring | redact)) as $titles |
  def cell: tostring | gsub("[\r\n]+"; " ") | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
    | gsub("\\|"; "\\|");
  def nowrap: gsub("-"; "‑");
  def name:
    if (.key | type) == "string" and .key != "" then
      (if $jira == "" then (.key | nowrap) else "[\(.key | nowrap)](\($jira)/browse/\(.key))" end)
    elif ((.prs // []) | length) > 0 then "[#\(.prs[0])](\($repo_url)/pull/\(.prs[0]))"
    else "?" end;
  # Titles are plain text, so their Markdown is shown as is; notes may use Markdown on purpose.
  def plain: gsub("(?<c>[\\\\`*_\\[\\]!#~])"; "\\\(.c)");
  def title: (if (.key | type) == "string" then $titles[.key] else null end) // .title // "" | tostring | plain | cell;
  def icon: {"fail": "🐞", "needs-human": "👀", "pass": "✅", "not-testable": "➖"}[.verdict] // "❓";
  def rank: {"fail": 0, "needs-human": 1, "pass": 2}[.verdict] // 3;
  walk(if type == "string" then redact else . end)
  | [.tickets[]? | objects] | sort_by(rank)
  | if length == 0 then empty else
      $headers, "|---|---|---|",
      (.[] | "| \(name) | \(icon) \(.verdict // "?" | cell | nowrap) | "
        + (title | if . == "" then "" else "**\(.)**<br>" end) + (.summary_line // "" | cell) + " |")
    end' "$OUTPUT/results.json")
# No tickets is no table; a results file jq can't read fails the step above, with a warning.
[[ -n "$table" ]] || exit 0

# awk also keeps a last line without a newline; ENVIRON keeps the backslashes of the table as they are.
TABLE="$table" awk '
  { lines[++n] = $0 }
  !at && /^<!-- tickets -->[[:space:]]*$/ { at = n }
  END {
    if (!at) printf "%s\n\n", ENVIRON["TABLE"]
    for (i = 1; i <= n; i++) print (i == at ? ENVIRON["TABLE"] : lines[i])
  }
' "$REPORT" > "$REPORT.tmp"
mv "$REPORT.tmp" "$REPORT"
