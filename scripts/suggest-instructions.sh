#!/usr/bin/env bash
# Opens or updates one draft PR with the agent's suggested improvements to the project's markdown files.
# Only plain .md files directly in the project folder are taken over; everything else is ignored.
#
# Env:
#   SUGGESTIONS_DIR  the agent's output/instructions folder
#   REPO_DIR         a fresh checkout of the project's default branch
#   PROJECT_DIR      folder of the markdown files in the project (default: .qa-agent)
#   BRANCH           branch of the PR (default: qa-agent/instructions)
#   PR_TITLE         default: "docs: improve the QA agent instructions"
#   RUN_URL          link to the run, for the PR description
#   DRY_RUN=true     show the changes instead of pushing and opening a PR
#   GH_TOKEN         token with contents: write and pull-requests: write

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-.qa-agent}"
BRANCH="${BRANCH:-qa-agent/instructions}"
PR_TITLE="${PR_TITLE:-docs: improve the QA agent instructions}"

if ! compgen -G "$SUGGESTIONS_DIR/*.md" > /dev/null; then
  echo "The agent suggested no changes to the instructions."
  exit 0
fi

mkdir -p "$REPO_DIR/$PROJECT_DIR"
for file in "$SUGGESTIONS_DIR"/*.md; do
  name=$(basename "$file")
  if [[ "$name" == "REASON.md" || ! "$name" =~ ^[A-Za-z0-9._-]+\.md$ ]]; then
    continue
  fi
  cp "$file" "$REPO_DIR/$PROJECT_DIR/$name"
done

cd "$REPO_DIR"
git add -- "$PROJECT_DIR"/*.md
if git diff --cached --quiet; then
  echo "The suggested instructions equal the current ones."
  exit 0
fi

reason="No reason given."
[[ -f "$SUGGESTIONS_DIR/REASON.md" ]] && reason=$(head -c 20000 "$SUGGESTIONS_DIR/REASON.md")
body=$(printf '%s\n\n---\nSuggested by the QA agent in %s. Review before merging: the agent may be wrong.\n' \
  "$reason" "${RUN_URL:-a QA run}")

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  git diff --cached --stat
  echo "--- PR: $PR_TITLE"
  echo "$body"
  exit 0
fi

base=$(git rev-parse --abbrev-ref HEAD)
git switch -q -C "$BRANCH"
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "$PR_TITLE"
# The branch belongs to the QA agent: every run rebuilds it from the default branch with its latest suggestion.
git push -q --force origin "$BRANCH"

existing=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty')
if [[ -n "$existing" ]]; then
  gh pr edit "$existing" --body "$body" > /dev/null
  echo "Updated PR #$existing with the suggested instructions."
else
  gh pr create --draft --base "$base" --head "$BRANCH" --title "$PR_TITLE" --body "$body"
fi
