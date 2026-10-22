#!/usr/bin/env bash
# Prints the milestones that have just become ready to start.
#
#   .github/scripts/ready.sh A1 [A2 ...]     the IDs that were just merged
#
# A milestone is ready when it is not merged itself, every dependency is merged
# (see deps.sh), and at least one dependency is among the IDs you pass. So each
# milestone is announced once, at the moment its last dependency lands.
# One line per ready milestone, tab separated: ID, owner, branch, title.
set -uo pipefail
cd "$(dirname "$0")/../.."

newly=" $(printf '%s ' "$@" | tr '[:lower:]' '[:upper:]')"
listed=$(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')

for brief in docs/milestones/*.md; do
  id=$(basename "$brief" .md)
  [ "$id" = M0 ] && continue
  printf '%s\n' "$listed" | grep -qx "$id" && continue
  .github/scripts/deps.sh --quiet "$id" || continue
  fresh=0
  for dep in $(.github/scripts/deps.sh --list "$id"); do
    case "$newly" in *" $dep "*) fresh=1 ;; esac
  done
  [ "$fresh" -eq 1 ] || continue
  case "$id" in INT) key=INT ;; *) key=${id:0:1} ;; esac
  owner=$(awk -v k="$key" '$1 == k {print $2; exit}' .github/owners.txt)
  branch=$(grep -m1 -E '^\| \*\*Branch\*\* \|' "$brief" | sed -E 's/.*`([^`]+)`.*/\1/')
  title=$(head -1 "$brief" | sed -E 's/^# *//')
  printf '%s\t%s\t%s\t%s\n' "$id" "${owner:--}" "$branch" "$title"
done
