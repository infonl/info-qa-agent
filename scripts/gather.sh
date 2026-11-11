#!/usr/bin/env bash
# Collects the merged PRs of a window, their trimmed diffs and Jira tickets, so the agent never needs
# GitHub or Jira credentials. Run from the checkout of the project under test.
#
# Env:
#   SCOPE              yesterday | <N>d | since:YYYY-MM-DD   (default: yesterday)
#                      "yesterday" is the previous working day, so on Monday it covers Friday to Sunday.
#   BASE_BRANCH        branch the PRs are merged into (default: main)
#   APP_PATHS          regex; a PR is tested when it changes a file matching it (default: every file)
#   SKIP_AUTHORS       comma separated PR authors to skip (default: Renovate and Dependabot)
#   MAX_PRS            maximum number of PRs handed to the agent, newest first (default: 15)
#   MAX_DIFF_LINES     maximum lines per trimmed diff (default: 1500)
#   JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN   optional, Jira Cloud; without them no tickets are fetched
#   JIRA_PROJECT_KEYS  comma separated, e.g. "PZ,WEB" (default: any KEY-123 looking text)
#   OUT_DIR            output directory (default: context)
#   GH_TOKEN           token for the gh CLI

set -euo pipefail

SCOPE="${SCOPE:-yesterday}"
BASE_BRANCH="${BASE_BRANCH:-main}"
APP_PATHS="${APP_PATHS:-.}"
SKIP_AUTHORS="${SKIP_AUTHORS:-app/renovate,app/dependabot,renovate[bot],dependabot[bot]}"
MAX_PRS="${MAX_PRS:-15}"
MAX_DIFF_LINES="${MAX_DIFF_LINES:-1500}"
OUT="${OUT_DIR:-context}"

rm -rf "$OUT"
mkdir -p "$OUT/diffs" "$OUT/jira"

# GNU date on the runner, gdate on macOS for local runs.
DATE="date"
command -v gdate > /dev/null && DATE="gdate"

case "$SCOPE" in
  yesterday)
    UNTIL=$($DATE -u -d yesterday +%F)
    if [[ $($DATE -u +%u) == 1 ]]; then SINCE=$($DATE -u -d '3 days ago' +%F); else SINCE=$UNTIL; fi
    ;;
  since:*) SINCE="${SCOPE#since:}"; UNTIL=$($DATE -u +%F) ;;
  *d) SINCE=$($DATE -u -d "${SCOPE%d} days ago" +%F); UNTIL=$($DATE -u +%F) ;;
  *) echo "Unknown scope '$SCOPE' (use yesterday | <N>d | since:YYYY-MM-DD)" >&2; exit 1 ;;
esac
echo "Collecting PRs merged into $BASE_BRANCH from $SINCE to $UNTIL (scope: $SCOPE)"

gh pr list --state merged --base "$BASE_BRANCH" --search "merged:$SINCE..$UNTIL" --limit 300 \
  --json number,title,body,headRefName,mergedAt,mergeCommit,author,url,files \
  > "$OUT/all-prs.json"

jq --arg app_paths "$APP_PATHS" --arg skip_authors "$SKIP_AUTHORS" '
  ($skip_authors | split(",") | map(gsub("^ +| +$"; ""))) as $skip
  | def skip_reason:
      if (.author.login as $login | $skip | index($login)) or (.title | test("^(chore|fix|build)\\(deps"))
        then "dependency update"
      elif ([.files[].path | select(test($app_paths))] | length) == 0 then "no application code changed"
      else null end;
  map(. + {skip_reason: skip_reason})
  | sort_by(.mergedAt) | reverse
' "$OUT/all-prs.json" > "$OUT/classified.json"

jq --argjson max "$MAX_PRS" '[.[] | select(.skip_reason == null)][:$max] | map(del(.skip_reason))' \
  "$OUT/classified.json" > "$OUT/prs.json"
jq --argjson max "$MAX_PRS" '
  ([.[] | select(.skip_reason == null)][$max:] | map(.skip_reason = "over the max-prs limit"))
  + [.[] | select(.skip_reason != null)]
  | map({number, title, url, skip_reason})
' "$OUT/classified.json" > "$OUT/skipped.json"
rm "$OUT/all-prs.json" "$OUT/classified.json"

PR_COUNT=$(jq length "$OUT/prs.json")
SKIPPED_COUNT=$(jq length "$OUT/skipped.json")
echo "Testable PRs: $PR_COUNT, skipped: $SKIPPED_COUNT"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "pr_count=$PR_COUNT"
    echo "since=$SINCE"
    echo "until=$UNTIL"
  } >> "$GITHUB_OUTPUT"
fi

if [[ -n "${JIRA_PROJECT_KEYS:-}" ]]; then
  KEY_RE="($(tr -d ' ' <<< "$JIRA_PROJECT_KEYS" | tr ',' '|'))-[0-9]+"
else
  KEY_RE='[A-Z][A-Z0-9]{1,9}-[0-9]+'
fi

: > "$OUT/pr-keys.tsv"
for number in $(jq -r '.[].number' "$OUT/prs.json"); do
  text=$(jq -r --argjson n "$number" '.[] | select(.number == $n) | "\(.title)\n\(.headRefName)\n\(.body // "")"' "$OUT/prs.json")
  keys=$(grep -oE "$KEY_RE" <<< "$text" | sort -u | paste -sd, - || true)
  printf '%s\t%s\n' "$number" "$keys" >> "$OUT/pr-keys.tsv"

  # The local diff has no size limit, unlike the GitHub API. Lock files, generated code and
  # snapshots cost tokens and tell the agent nothing about behaviour.
  merge_commit=$(jq -r --argjson n "$number" '.[] | select(.number == $n) | .mergeCommit.oid' "$OUT/prs.json")
  if git cat-file -e "$merge_commit" 2> /dev/null; then
    # Without pipefail, because head closing the pipe early on a long diff is not an error.
    (
      set +o pipefail
      git show --format= --no-color "$merge_commit" -- . \
        ':(exclude)**/package-lock.json' ':(exclude)**/yarn.lock' ':(exclude)**/pnpm-lock.yaml' \
        ':(exclude)**/generated/**' ':(exclude)**/*.snap' ':(exclude)**/*.svg' \
        | head -n "$MAX_DIFF_LINES" > "$OUT/diffs/$number.diff"
    )
  else
    echo "warn: merge commit of #$number not found, is the checkout shallow? Use fetch-depth: 0" >&2
  fi
done

jira_issue() {
  curl -sS --fail-with-body -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H "Accept: application/json" \
    "$JIRA_BASE_URL/rest/api/3/issue/$1?expand=renderedFields&fields=summary,status,issuetype,description,comment,parent"
}

# Rendered HTML reduced to plain text: the agent needs the words, not the markup.
JQ_TEXT='def text: (. // "") | gsub("<br ?/?>|</p>|</li>|</h[1-6]>"; "\n") | gsub("<li>"; "- ") | gsub("<[^>]+>"; "")
  | gsub("&nbsp;"; " ") | gsub("&amp;"; "&") | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"")
  | gsub("&#39;"; "'"'"'") | gsub("\n{3,}"; "\n\n");'

if [[ -n "${JIRA_BASE_URL:-}" && -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
  for key in $(cut -f2 "$OUT/pr-keys.tsv" | tr ',' '\n' | grep -v '^$' | sort -u); do
    if ! raw=$(jira_issue "$key"); then
      echo "warn: could not fetch Jira issue $key" >&2
      continue
    fi
    # Sub-tasks are often empty; the intent lives on the parent story.
    parent_description=""
    if [[ $(jq -r '.fields.issuetype.subtask' <<< "$raw") == "true" ]]; then
      parent_key=$(jq -r '.fields.parent.key' <<< "$raw")
      parent_description=$(jira_issue "$parent_key" | jq -r "$JQ_TEXT .renderedFields.description | text" || true)
    fi
    jq --arg base "$JIRA_BASE_URL" --arg parent_description "$parent_description" "$JQ_TEXT"'
      {
        key,
        url: "\($base)/browse/\(.key)",
        summary: .fields.summary,
        type: .fields.issuetype.name,
        status: .fields.status.name,
        parent: (.fields.parent | if . then "\(.key): \(.fields.summary)" else null end),
        parent_description: (if $parent_description != "" then $parent_description else null end),
        description: (.renderedFields.description | text),
        last_comments: [.renderedFields.comment.comments[-5:][]? | .body | text]
      }' <<< "$raw" > "$OUT/jira/$key.json"
  done
else
  echo "No Jira credentials, testing from the PR descriptions and diffs only."
fi

{
  echo "# QA context"
  echo
  echo "- Scope: \`$SCOPE\`, PRs merged into \`$BASE_BRANCH\` from $SINCE to $UNTIL"
  echo "- PRs to test: $PR_COUNT (the $SKIPPED_COUNT others are listed in skipped.json and need no testing)"
  echo "- Jira tickets fetched: $(find "$OUT/jira" -name '*.json' | wc -l | tr -d ' ')"
  echo
  echo "| PR | Title | Tickets | Diff |"
  echo "|----|-------|---------|------|"
  while IFS=$'\t' read -r number keys; do
    title=$(jq -r --argjson n "$number" '.[] | select(.number == $n) | .title | gsub("\\|"; "/")' "$OUT/prs.json")
    echo "| #$number | $title | ${keys:-none} | diffs/$number.diff |"
  done < "$OUT/pr-keys.tsv"
} > "$OUT/manifest.md"

echo "Context written to $OUT/"
