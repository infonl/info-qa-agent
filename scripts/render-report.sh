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

# Files, not arguments or variables, so many tickets never hit a size limit.
TITLES=$(mktemp)
TABLE=$(mktemp)
trap 'rm -f "$TITLES" "$TABLE"' EXIT
find "$CONTEXT/jira" -name '*.json' -exec cat {} + 2> /dev/null \
  | jq -s 'map({(.key): .summary}) | add // {}' > "$TITLES" 2> /dev/null || echo '{}' > "$TITLES"
[[ -s "$TITLES" ]] || echo '{}' > "$TITLES"

# Keys and verdicts get non-breaking hyphens so they never wrap; text is escaped, so a title such as
# "Fix <input> validation" shows as text and a | doesn't split the cell.
jq -r --arg jira "${JIRA_BASE_URL:-}" --arg repo_url "$REPO_URL" --arg headers "$HEADERS" \
  --slurpfile titles "$TITLES" '
  def redact: reduce ([$ENV.QA_PASSWORD, $ENV.QA_PASSWORD_2][] | select(type == "string" and length >= 4)) as $s
    (.; split($s) | join($s | gsub("."; "*")));
  # Passwords go before anything is escaped: an escaped password no longer matches the scrub.
  # A missing or empty Jira title falls back to the title from the agent.
  ($titles[0] | map_values(select(type == "string" and length > 0) | redact)) as $titles |
  def cell: tostring | gsub("[\r\n]+"; " ") | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
    | gsub("\\|"; "\\|");
  def nowrap: gsub("-"; "‑");
  # Only a real key or PR number goes into a link; anything else could break the row or the link.
  def key: .key | if type == "string" and test("^[A-Z][A-Z0-9_]*-[0-9]+$") then . else null end;
  def pr: [.prs[]? | select(type == "number" and . > 0 and . == floor)][0];
  def name:
    if key then
      (if $jira == "" then (key | nowrap) else "[\(key | nowrap)](\($jira)/browse/\(key))" end)
    elif pr then "[#\(pr)](\($repo_url)/pull/\(pr))"
    else "?" end;
  # Titles are plain text, so their Markdown is shown as is; notes may use Markdown on purpose.
  def plain: gsub("(?<c>[\\\\`*_\\[\\]!#~])"; "\\\(.c)");
  def title: (if key then $titles[key] else null end) // .title // "" | tostring | plain | cell;
  def icon: {"fail": "🐞", "needs-human": "👀", "pass": "✅", "not-testable": "➖"}[.verdict] // "❓";
  def rank: {"fail": 0, "needs-human": 1, "pass": 2}[.verdict] // 3;
  walk(if type == "string" then redact else . end)
  | [.tickets[]? | objects] | sort_by(rank)
  | if length == 0 then empty else
      $headers, "|---|---|---|",
      (.[] | "| \(name) | \(icon) \(.verdict // "?" | cell | nowrap) | "
        + (title | if . == "" then "" else "**\(.)**<br>" end) + (.summary_line // "" | cell) + " |")
    end' "$OUTPUT/results.json" > "$TABLE"
# No tickets is no table; a results file jq can't read fails the step above, with a warning.
[[ -s "$TABLE" ]] || exit 0

# awk also keeps a last line without a newline. The first file is the table, the second the report.
awk '
  NR == FNR { table = table (FNR > 1 ? "\n" : "") $0; next }
  { lines[++n] = $0 }
  !at && /^<!-- tickets -->[[:space:]]*$/ { at = n }
  END {
    if (!at) printf "%s\n\n", table
    for (i = 1; i <= n; i++) print (i == at ? table : lines[i])
  }
' "$TABLE" "$REPORT" > "$REPORT.tmp"
mv "$REPORT.tmp" "$REPORT"
