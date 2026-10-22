#!/usr/bin/env bash
# Fails when a milestone's dependencies are not merged yet.
#
#   .github/scripts/deps.sh B1
#
# The dependencies are the IDs in the "Depends on" row of docs/milestones/<ID>.md.
# A dependency counts as merged when its ID is on its own line in milestones.txt:
# every milestone's PR adds its own ID, so the list on your branch is main's list
# as of your last pull. check.sh then runs every listed milestone, so an ID cannot
# be listed without the milestone being built.
set -uo pipefail
cd "$(dirname "$0")/../.."

id=$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')
[ -n "$id" ] || { echo "Usage: .github/scripts/deps.sh <milestone>   e.g. .github/scripts/deps.sh B1"; exit 2; }
brief="docs/milestones/$id.md"
[ -f "$brief" ] || { echo "❌ $brief does not exist"; exit 1; }

row=$(grep -m1 -E '^\| \*\*Depends on\*\* \|' "$brief" || true)
[ -n "$row" ] || { echo "❌ $brief has no 'Depends on' row"; exit 1; }
row=$(printf '%s' "$row" | sed -E 's/^\| \*\*Depends on\*\* \| *//; s/ *\|$//')

# Expand ranges such as "A1 to A4", then pick up the single IDs.
deps=()
rest=$row
while [[ $rest =~ ([A-D])([0-9])\ to\ ([A-D])([0-9]) ]]; do
  letter=${BASH_REMATCH[1]}; from=${BASH_REMATCH[2]}; to=${BASH_REMATCH[4]}
  for ((n = from; n <= to; n++)); do deps+=("$letter$n"); done
  rest=${rest/"${BASH_REMATCH[0]}"/ }
done
for token in $(printf '%s' "$rest" | grep -oE '\b([A-D][0-9]|M0)\b' || true); do deps+=("$token"); done
if [ "${#deps[@]}" -eq 0 ]; then echo "❌ no milestone IDs found in the Depends on row of $brief: $row"; exit 1; fi

listed=$(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')
missing=()
seen=" "
echo "Dependencies of $id: $row"
for dep in "${deps[@]}"; do
  case "$seen" in *" $dep "*) continue ;; esac
  seen="$seen$dep "
  if printf '%s\n' "$listed" | grep -qx "$dep"; then
    echo "  ✅ $dep"
  else
    echo "  ❌ $dep is not merged yet"
    missing+=("$dep")
  fi
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Dependencies of $id"
    echo
    if [ "${#missing[@]}" -eq 0 ]; then echo "**👍 All merged:** ${seen}"; else echo "**👎 Not merged yet:** ${missing[*]}"; fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "❌ $id needs ${missing[*]} merged into main first."
  echo "   When it is: git checkout main && git pull, then git checkout <your branch> && git merge main."
  echo "   Until then, build a milestone whose dependencies are all merged (see the schedule in docs/overview.md)."
  exit 1
fi
echo "👍 Every dependency of $id is merged."
