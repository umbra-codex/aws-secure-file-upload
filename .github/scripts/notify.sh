#!/usr/bin/env bash
# Keeps the "<ID> is ready" issues in step with milestones.txt on main. Safe to
# run at any time, and it repairs whatever an earlier run missed:
#
#   1. closes the open "<ID> is ready" issue of every milestone that has merged;
#   2. opens one for every milestone that is ready and has none, assigned to its
#      owner from .github/owners.txt (GitHub emails the assignee);
#   3. assigns an open one that has no assignee yet, for an owner who has since
#      accepted the repository invitation.
#
# Needs the gh CLI with GH_TOKEN and GH_REPO set. DRY_RUN=1 prints instead of
# acting. Exits 1 if any gh call failed, so a bad token or disabled issues shows
# as a red run instead of a quiet one.
set -uo pipefail
cd "$(dirname "$0")/../.."

fail=0
run() {
  if [ "${DRY_RUN:-}" = 1 ]; then echo "DRY: $*"; return 0; fi
  "$@" || { echo "::error::failed: gh ${2:-} ${3:-}"; fail=1; return 1; }
}
# try: like run, but a failure is expected and is not an error (an owner who cannot be assigned yet).
try() {
  if [ "${DRY_RUN:-}" = 1 ]; then echo "DRY: $*"; return 0; fi
  "$@" >/dev/null 2>&1
}
owner_of() { case "$1" in INT) k=INT ;; *) k=${1:0:1} ;; esac; awk -v k="$k" '$1 == k {print $2; exit}' .github/owners.txt; }

issues=$(gh issue list --state all --limit 1000 --json number,title,state,assignees) || { echo "::error::cannot list issues (token, GH_REPO, or issues disabled?)"; exit 1; }
listed=$(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')
sha=${GITHUB_SHA:-}

# 1 and 3. Walk the open "ready" issues.
while IFS=$'\t' read -r num id assigned; do
  [ -n "$num" ] || continue
  if printf '%s\n' "$listed" | grep -qx "$id"; then
    run gh issue close "$num" --comment "$id is listed in milestones.txt on main${sha:+ (checked at ${sha:0:7})}, so it has merged."
  elif [ "$assigned" = 0 ]; then
    owner=$(owner_of "$id")
    [ -n "$owner" ] && try gh issue edit "$num" --add-assignee "$owner" && echo "$id: assigned to $owner"
  fi
done < <(printf '%s' "$issues" | jq -r '.[] | select(.state == "OPEN" and (.title | test("^[A-Z0-9]+ is ready:"))) | [.number, (.title | split(" ")[0]), (.assignees | length)] | @tsv')

# 2. Announce what is ready.
while IFS=$'\t' read -r id owner branch title; do
  [ -n "$id" ] || continue
  prefix="$id is ready:"
  if printf '%s' "$issues" | jq -e --arg p "$prefix" 'any(.[]; .title | startswith($p))' >/dev/null; then
    echo "$id: already announced"; continue
  fi
  subject=${title#*: }
  body="Every dependency of $id is merged, so you can start.

- Brief: docs/milestones/$id.md"
  if [ "$branch" != "-" ]; then
    body="$body
- Branch: \`$branch\` (use this exact name; the branch name picks the milestone that CI checks)
- Start: \`git checkout main && git pull && git checkout -b $branch && git push -u origin $branch\`"
  else
    echo "::warning::$id: no branch name found in its brief"
  fi
  [ "$owner" = "-" ] || body="$body

@$owner this one is yours."
  body="$body
This issue closes by itself when the milestone merges."
  if [ "$owner" != "-" ] && try gh issue create --title "$prefix $subject" --body "$body" --assignee "$owner"; then
    echo "$id: announced to $owner"
  elif run gh issue create --title "$prefix $subject" --body "$body"; then
    echo "::warning::$id: announced without an assignee (${owner} could not be assigned yet; the next run retries)"
  fi
done < <(.github/scripts/ready.sh)

exit "$fail"
