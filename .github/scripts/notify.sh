#!/usr/bin/env bash
# Tells the owner of each milestone that just became ready, and tidies up after a merge.
#
#   .github/scripts/notify.sh A1 [A2 ...]     the IDs that were just merged
#
# For every ID passed: close its open "<ID> is ready" issue. For every milestone
# that just became ready (ready.sh): open one "<ID> is ready" issue assigned to its
# owner, unless an issue with that title already exists. GitHub emails the assignee.
# Needs the gh CLI with GH_TOKEN and GH_REPO set. DRY_RUN=1 prints instead of acting.
set -uo pipefail
cd "$(dirname "$0")/../.."

run() { if [ "${DRY_RUN:-}" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }
sha=${GITHUB_SHA:-unknown}
issues=$(gh issue list --state all --limit 300 --json number,title,state 2>/dev/null || echo '[]')

# 1. A merged milestone's "ready" issue is done.
for id in "$@"; do
  for n in $(printf '%s' "$issues" | jq -r --arg p "$id is ready:" '.[] | select(.state == "OPEN" and (.title | startswith($p))) | .number'); do
    run gh issue close "$n" --comment "Merged to main in ${sha:0:7}."
  done
done

# 2. Announce what the merge unblocked.
while IFS=$'\t' read -r id owner branch title; do
  [ -n "$id" ] || continue
  prefix="$id is ready:"
  if printf '%s' "$issues" | jq -e --arg p "$prefix" 'any(.[]; .title | startswith($p))' >/dev/null; then
    echo "$id: already announced"; continue
  fi
  subject=${title#*: }
  body=$(cat <<BODY
Every dependency of $id is merged, so you can start.

- Brief: docs/milestones/$id.md
- Branch: \`$branch\` (use this exact name; the branch name picks the milestone that CI checks)
- Start: \`git checkout main && git pull && git checkout -b $branch && git push -u origin $branch\`

@$owner this one is yours. This issue closes by itself when the milestone merges.
BODY
)
  if [ "$owner" != "-" ] && run gh issue create --title "$prefix $subject" --body "$body" --assignee "$owner"; then
    echo "$id: announced to $owner"
  else
    run gh issue create --title "$prefix $subject" --body "$body"
    echo "$id: announced (no assignee: ${owner:-none} could not be assigned)"
  fi
done < <(.github/scripts/ready.sh "$@")
