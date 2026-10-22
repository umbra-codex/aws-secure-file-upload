#!/usr/bin/env bash
# Prints every milestone that is ready to start: not merged yet, and every
# dependency merged (see deps.sh). Run on main, where milestones.txt is the
# ledger of what has merged.
#
#   .github/scripts/ready.sh
#
# One line per ready milestone, tab separated: ID, owner, branch, title.
# A milestone whose brief cannot be read is reported on stderr and skipped.
set -uo pipefail
cd "$(dirname "$0")/../.."

listed=$(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')

for brief in docs/milestones/*.md; do
  file=$(basename "$brief" .md)
  id=$(printf '%s' "$file" | tr '[:lower:]' '[:upper:]')
  [ "$id" = M0 ] && continue
  if [ "$file" != "$id" ] || ! printf '%s' "$id" | grep -Eq '^([A-D][0-9]|INT)$'; then
    echo "::warning::$brief: the file name must be a milestone ID in capitals, such as B1 or INT" >&2; continue
  fi
  printf '%s\n' "$listed" | grep -qx "$id" && continue
  .github/scripts/deps.sh --quiet "$id"
  case $? in
    0) ;;
    1) continue ;;
    *) echo "::warning::$id: cannot evaluate its dependencies (run .github/scripts/deps.sh $id)" >&2; continue ;;
  esac
  case "$id" in INT) key=INT ;; *) key=${id:0:1} ;; esac
  owner=$(awk -v k="$key" '$1 == k {print $2; exit}' .github/owners.txt)
  branch=$(grep -m1 -E '^\| \*\*Branch\*\* \|' "$brief" | sed -nE 's/^[^`]*`([^`]+)`.*/\1/p')
  title=$(head -1 "$brief" | sed -E 's/^# *//')
  printf '%s\t%s\t%s\t%s\n' "$id" "${owner:--}" "${branch:--}" "$title"
done
