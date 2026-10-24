#!/usr/bin/env bash
# Keeps the "<ID> is ready" issues in step with milestones.txt on main. Safe to
# run at any time, and it repairs whatever an earlier run missed:
#
#   1. closes the open notice of every milestone that has merged;
#   2. opens one for every milestone that is ready and has none, assigned to its
#      owner from .github/owners.txt (GitHub emails the assignee);
#   3. assigns an open notice that has no assignee yet, for an owner who has
#      since accepted the repository invitation;
#   4. reopens a notice that was closed before its milestone merged.
#
# A notice is identified by the "ready-notice" label, not by its title, so a
# rename keeps it trackable and an issue someone created by hand is never
# mistaken for one. The list is filtered by that label, so its size is the number
# of notices (one per milestone), not the number of issues in the repository. The
# title still names the milestone, and a labelled issue whose title no longer
# does stops the run with an error naming it.
#
# An issue a person closed or renamed by hand is drift from the ledger, not a
# decision this workflow can read: the next run puts a closed unmerged notice
# back and keeps tracking a renamed one, and a red run asks for the title.
#
# Needs the gh CLI with GH_TOKEN and GH_REPO set. DRY_RUN=1 prints instead of
# acting; with ISSUES_FILE=<json> it also reads the issue list from that file
# instead of the API, so a dry run needs no token. Exits 1 if a call that must
# work failed, so a bad token, disabled issues, or an unreadable brief shows as
# a red run instead of a quiet one. An owner who cannot be assigned yet is a
# warning, not a failure: that state is expected and the next run retries it.
#
# No `set -e` on purpose: every failure is recorded in `fail` and the pass
# continues, so one failed close does not skip the announcements.
set -uo pipefail
cd "$(dirname "$0")/../.."

LABEL=ready-notice
fail=0

run() {
  # Do not simplify this to a bare "$@": the `fail` flag is the only record of a
  # failure that must still let the rest of the pass run.
  if [ "${DRY_RUN:-}" = 1 ]; then echo "DRY: $*"; return 0; fi
  "$@" || { echo "::error::failed: $1 ${2:-} ${3:-}"; fail=1; return 1; }
}
# try: like run, but a failure is expected and is not an error (an owner who cannot be assigned yet).
try() {
  if [ "${DRY_RUN:-}" = 1 ]; then echo "DRY: $*"; return 0; fi
  "$@" >/dev/null 2>&1
}
owner_of() { case "$1" in INT|SHIP) k=$1 ;; *) k=${1:0:1} ;; esac; awk -v k="$k" '$1 == k {print $2; exit}' .github/owners.txt; }

# One assignment path for the first run and for every retry, so a wrong handle
# is reported every run instead of only once.
assign() {
  local num=$1 id=$2 owner=$3
  if try gh issue edit "$num" --add-assignee "$owner"; then
    [ "${DRY_RUN:-}" = 1 ] || echo "$id: assigned to $owner"
    return 0
  fi
  if gh api "users/$owner" >/dev/null 2>&1; then
    echo "::warning::$id: could not assign @$owner yet (invitation not accepted?); #$num stays unassigned and the next run retries"
  else
    echo "::warning::$id: no GitHub user @$owner (check .github/owners.txt); #$num stays unassigned"
  fi
  return 1
}

# The label is the durable identity of a notice, so it must exist before the
# list below can be trusted: an unknown label makes `issue list --label` return
# an empty list, which would look like "nothing announced yet" and duplicate
# every notice.
if [ "${DRY_RUN:-}" = 1 ]; then
  echo "DRY: gh label create $LABEL"
else
  gh label create "$LABEL" --color 1D76DB --description 'Opened by the next workflow; read by it on every run' >/dev/null 2>&1 || true
  if ! gh label list --search "$LABEL" --limit 100 --json name 2>/dev/null | jq -r '.[].name' | grep -qx "$LABEL"; then
    echo "::error::the $LABEL label does not exist and cannot be created (does the token have issues: write?); the notices would have no identity without it"
    exit 1
  fi
fi

if [ "${DRY_RUN:-}" = 1 ] && [ -n "${ISSUES_FILE:-}" ]; then
  # The fixture stands in for `gh issue list --label`, so filter it the same way.
  issues=$(jq --arg l "$LABEL" '[ .[] | select((.labels // []) | map(.name) | index($l)) ]' "$ISSUES_FILE") ||
    { echo "::error::cannot read ISSUES_FILE $ISSUES_FILE"; exit 1; }
elif [ "${DRY_RUN:-}" = 1 ]; then
  # A dry run must not need a token to show what it would do.
  if ! issues=$(gh issue list --state all --label "$LABEL" --limit 1000 --json number,title,state,labels,assignees 2>&1); then
    echo "::notice::DRY_RUN: cannot list issues here, so this run assumes there are none"
    issues='[]'
  fi
else
  issues=$(gh issue list --state all --label "$LABEL" --limit 1000 --json number,title,state,labels,assignees) ||
    { echo "::error::cannot list issues (token, GH_REPO, or issues disabled?)"; exit 1; }
fi
printf '%s' "$issues" | jq -e 'type == "array"' >/dev/null 2>&1 ||
  { echo "::error::the issue list is not a JSON array"; exit 1; }

if [ ! -s milestones.txt ]; then
  echo "::error::milestones.txt is missing or empty; there is no record of what has merged"
  exit 1
fi
listed=$(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')
if [ -z "$listed" ]; then
  echo "::error::milestones.txt holds no milestone IDs"
  exit 1
fi
sha=${GITHUB_SHA:-}

# 1, 3 and 4. Walk the notices: close the merged, repair the rest.
# The map is (number state assignee-count) per milestone ID, used by pass 2.
declare -A notice_num=() notice_state=()
blocked=0
while IFS=$'\t' read -r num state title assigned; do
  [ -n "$num" ] || continue
  if [[ $title =~ ^([A-D][0-9]|INT|SHIP)\ is\ ready: ]]; then
    id=${BASH_REMATCH[1]}
  elif [[ $title =~ (^|[^A-Za-z0-9])([A-D][0-9]|INT|SHIP)([^A-Za-z0-9]|$) ]]; then
    id=${BASH_REMATCH[2]}
    echo "::warning::#$num: its title no longer starts with \"<ID> is ready:\", but it still names $id, so the label keeps it tracked"
  else
    echo "::error::#$num has the $LABEL label but its title does not name a milestone. Rename it to \"A3 is ready: ...\". This run opens no new notices, because it cannot tell whether #$num is the notice for a ready milestone."
    fail=1
    blocked=1
    continue
  fi
  if [ -n "${notice_num[$id]:-}" ]; then
    echo "::warning::$id: two notices (#${notice_num[$id]} and #$num); close one by hand"
    continue
  fi
  notice_num[$id]=$num notice_state[$id]=$state
  if printf '%s\n' "$listed" | grep -qx "$id"; then
    if [ "$state" = OPEN ]; then
      run gh issue close "$num" --comment "$id is listed in milestones.txt on main${sha:+ (checked at ${sha:0:7})}, so it has merged." &&
        echo "$id: closed #$num"
    fi
  elif [ "$state" = CLOSED ]; then
    # Closed while the milestone is still unmerged: someone closed it by hand, or
    # a PR closed it by accident. Reopen rather than open a duplicate.
    run gh issue reopen "$num" --comment "Reopened: $id has not merged yet, so this notice is still current." ||
      { echo "::error::$id: #$num is closed but $id has not merged; reopen it by hand"; continue; }
    echo "$id: reopened #$num"
    notice_state[$id]=OPEN
    if [ "$assigned" = 0 ]; then
      owner=$(owner_of "$id")
      if [ -n "$owner" ]; then assign "$num" "$id" "$owner"; else echo "::warning::$id: no owner for this milestone in .github/owners.txt"; fi
    fi
  elif [ "$assigned" = 0 ]; then
    owner=$(owner_of "$id")
    if [ -n "$owner" ]; then assign "$num" "$id" "$owner"; else echo "::warning::$id: no owner for this milestone in .github/owners.txt"; fi
  fi
done < <(printf '%s' "$issues" | jq -r '.[] | [.number, .state, .title, (.assignees | length)] | @tsv')

# 2. Announce what is ready.
ready_out=$(.github/scripts/ready.sh)
ready_rc=$?
if [ "$ready_rc" -ne 0 ]; then
  echo "::error::ready.sh exited $ready_rc: at least one brief cannot be read, so that milestone could never be announced. The notices for the briefs that were readable were still reconciled. Fix the brief, then run this workflow again."
  fail=1
fi

while IFS=$'\t' read -r id owner branch title; do
  [ -n "$id" ] || continue
  prefix="$id is ready:"
  if [ -n "${notice_num[$id]:-}" ]; then
    echo "$id: already announced (#${notice_num[$id]}, ${notice_state[$id]})"
    continue
  fi
  if [ "$blocked" = 1 ]; then
    echo "::warning::$id: not announced this run; a labelled notice has a title this run cannot read (see the error above)"
    continue
  fi
  emdash=$'\u2014'
  subject=${title#"$id: "}
  subject=${subject#"$id $emdash "}
  subject=${subject#"$id - "}
  subject=${subject#"$id "}
  [ -n "$subject" ] || subject=$title
  body="Every dependency of $id is merged, so you can start.

- Brief: docs/milestones/$id.md"
  if [ "$branch" != "-" ]; then
    body="$body
- Branch: \`$branch\` (use this exact name; the branch name picks the milestone that CI checks)
- Start: \`git checkout main && git pull && git checkout -b $branch && git push -u origin $branch\`"
  else
    echo "::warning::$id: no usable branch name in its brief; the notice is opened without one"
  fi
  [ "$owner" = "-" ] || body="$body

@$owner this one is yours."
  body="$body
This issue closes by itself when the milestone merges."

  if [ "${DRY_RUN:-}" = 1 ]; then
    echo "DRY: gh issue create --title \"$prefix $subject\" --label $LABEL${owner:+ --assignee $owner}"
    continue
  fi
  if [ "$owner" = "-" ]; then
    echo "::warning::$id: no owner for this milestone in .github/owners.txt, so nobody is notified"
  fi
  if ! url=$(gh issue create --title "$prefix $subject" --body "$body" --label "$LABEL" 2>&1); then
    echo "::error::cannot open the \"$prefix\" issue: $url"
    fail=1
    continue
  fi
  last=$(printf "%s\n" "$url" | tail -n 1)
  num=${last##*/}
  echo "$id: announced as #$num"
  [ "$owner" = "-" ] || assign "$num" "$id" "$owner"
done <<< "$ready_out"

exit "$fail"
