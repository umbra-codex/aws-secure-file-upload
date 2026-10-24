#!/usr/bin/env bash
# Prints every milestone that is ready to start: not merged yet, and every
# dependency merged (see deps.sh). Run on main, where milestones.txt is the
# ledger of what has merged.
#
#   .github/scripts/ready.sh
#
# One line per ready milestone, tab separated: ID, owner, branch, title.
# A brief whose row cannot be read is reported on stderr and the exit status is
# 1, because a milestone that can never be announced is a defect in the briefs,
# not a quiet no-op. Exit 0 means every brief was read and every skip was "its
# dependencies are not merged yet".
#
# No `set -e` on purpose: the `&& continue` idioms below and deps.sh's exit
# status are read by hand, so a nonzero status must not abort the pass.
set -uo pipefail
cd "$(dirname "$0")/../.."

status=0
ledger=milestones.txt
if [ ! -s "$ledger" ]; then
  echo "::error::$ledger is missing or empty; there is no record of what has merged" >&2
  exit 1
fi
listed=$(grep -Ev '^[[:space:]]*(#|$)' "$ledger" | tr -d ' \r')
if [ -z "$listed" ]; then
  echo "::error::$ledger holds no milestone IDs" >&2
  exit 1
fi

count=0
for brief in docs/milestones/*.md; do
  [ -f "$brief" ] || continue
  count=$((count + 1))
  file=$(basename "$brief" .md)
  id=$(printf '%s' "$file" | tr '[:lower:]' '[:upper:]')
  [ "$id" = M0 ] && continue
  if [ "$file" != "$id" ] || ! printf '%s' "$id" | grep -Eq '^([A-D][0-9]|INT|SHIP)$'; then
    echo "::error::$brief: the file name must be a milestone ID in capitals, such as B1, INT or SHIP" >&2
    status=1
    continue
  fi
  printf '%s\n' "$listed" | grep -qx "$id" && continue
  .github/scripts/deps.sh --quiet "$id"
  rc=$?
  case $rc in
    0) ;;
    1) continue ;;
    *)
      echo "::error::$id: cannot evaluate its dependencies (deps.sh exited $rc; run .github/scripts/deps.sh $id)" >&2
      status=1
      continue
      ;;
  esac
  case "$id" in INT|SHIP) key=$id ;; *) key=${id:0:1} ;; esac
  owner=$(awk -v k="$key" '$1 == k {print $2; exit}' .github/owners.txt)
  # The branch name decides which milestone CI checks (the pattern in ci.yml), so
  # a name CI cannot read is worse than no name: say so and ask for a fix.
  branch=$(grep -m1 -E '^\| \*\*Branch\*\* \|' "$brief" | sed -nE 's/^[^`]*`([^`]+)`.*/\1/p')
  if [ -n "$branch" ] && ! printf '%s' "$branch" | grep -Eq '^([a-dA-D][0-9]|[iI][nN][tT]|[sS][hH][iI][pP])([-_][A-Za-z0-9._-]*)?$'; then
    echo "::warning::$brief: the Branch cell \"$branch\" is not a name CI reads a milestone from; use ${id,,}-<words>, for example ${id,,}-buckets" >&2
    branch=""
  fi
  title=$(head -1 "$brief" | sed -E 's/^# *//')
  title=${title//$'\t'/ }
  title=${title%$'\r'}
  printf '%s\t%s\t%s\t%s\n' "$id" "${owner:--}" "${branch:--}" "$title"
done

if [ "$count" -lt 17 ]; then
  echo "::error::found $count briefs in docs/milestones; expected at least 17. A brief that is missing from the checkout can never be announced" >&2
  exit 1
fi
exit "$status"
