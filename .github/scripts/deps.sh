#!/usr/bin/env bash
# Checks that a milestone's dependencies are merged.
#
#   .github/scripts/deps.sh B1             check, with a readable report
#   .github/scripts/deps.sh --quiet B1     exit status only, no output
#   .github/scripts/deps.sh --list B1      print the dependency IDs, one per line
#
# The dependencies are the IDs in the "Depends on" row of docs/milestones/<ID>.md.
# That row is the contract this gate enforces: docs/milestones/ is code-owned
# (CODEOWNERS), so changing a row needs the lead's review like any other rule.
# A dependency is merged when its ID is on its own line in milestones.txt. The list
# on your branch is main's list as of your last pull, so when origin/main is
# available (CI fetches it) the report also says "merged on main, not in your
# branch yet" instead of "not merged yet".
#
# Exit status: 0 all merged, 1 a dependency is not merged, 2 usage, 3 the brief
# cannot be read (missing file, no Depends on row, or a range this script does not
# understand).
set -uo pipefail
cd "$(dirname "$0")/../.."

mode=check
case "${1:-}" in --quiet) mode=quiet; shift ;; --list) mode=list; shift ;; esac
[ "$mode" != quiet ] || { exec >/dev/null 2>&1; GITHUB_STEP_SUMMARY=; }

id=$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')
[ -n "$id" ] || { echo "Usage: .github/scripts/deps.sh [--quiet|--list] <milestone>   e.g. .github/scripts/deps.sh B1"; exit 2; }
brief="docs/milestones/$id.md"
[ -f "$brief" ] || { echo "❌ $brief does not exist"; exit 3; }

row=$(grep -m1 -E '^\| \*\*Depends on\*\* \|' "$brief" || true)
[ -n "$row" ] || { echo "❌ $brief has no 'Depends on' row"; exit 3; }
row=$(printf '%s' "$row" | sed -E 's/^\| \*\*Depends on\*\* \| *//; s/ *\|$//')
# Work in capitals, so "A1 to A4" and "A1 TO A4" are the same range.
row=$(printf '%s' "$row" | tr '[:lower:]' '[:upper:]')

# Expand ranges such as "A1 to A4" (same letter only), then pick up the single IDs.
deps=()
rest=$row
while [[ $rest =~ ([A-D])([0-9])\ TO\ ([A-D])([0-9]) ]]; do
  letter=${BASH_REMATCH[1]}; from=${BASH_REMATCH[2]}; end_letter=${BASH_REMATCH[3]}; to=${BASH_REMATCH[4]}
  if [ "$letter" != "$end_letter" ] || [ "$from" -gt "$to" ]; then
    echo "❌ $brief: the range ${BASH_REMATCH[0]} must stay within one letter and count upward"; exit 3
  fi
  for ((n = from; n <= to; n++)); do deps+=("$letter$n"); done
  rest=${rest/"${BASH_REMATCH[0]}"/ }
done
# Refuse any other way of writing a range, so a brief edit cannot silently drop dependencies.
if printf '%s' "$rest" | grep -Eq $'[A-D][0-9][[:space:]]*(-|\u2013|\u2014|\\.\\.|THROUGH|TO)[[:space:]]*[A-D][0-9]'; then
  echo "❌ $brief: a range in the Depends on row is not written as 'A1 to A4'"; exit 3
fi
# SHIP sits after INT, so a brief that depends on either one by name must have
# that dependency read as well.
for token in $(printf '%s' "$rest" | grep -oE '\b([A-D][0-9]|M0|INT|SHIP)\b' || true); do deps+=("$token"); done
[ "${#deps[@]}" -gt 0 ] || { echo "❌ no milestone IDs found in the Depends on row of $brief"; exit 3; }

# De-duplicate, keeping order.
uniq_deps=(); seen=" "
for dep in "${deps[@]}"; do
  case "$seen" in *" $dep "*) continue ;; esac
  seen="$seen$dep "; uniq_deps+=("$dep")
done
if [ "$mode" = list ]; then printf '%s\n' "${uniq_deps[@]}"; exit 0; fi

ids_of() { grep -Ev '^[[:space:]]*(#|$)' | tr -d ' \r'; }
branch_ledger=$(ids_of < milestones.txt)
main_ledger=""
if git rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then
  main_ledger=$(git show origin/main:milestones.txt 2>/dev/null | ids_of || true)
fi

missing=(); stale=()
[ -n "$main_ledger" ] || echo "(origin/main is not fetched here, so this compares with your branch only)"
echo "Dependencies of $id: ${uniq_deps[*]}"
for dep in "${uniq_deps[@]}"; do
  if printf '%s\n' "$branch_ledger" | grep -qx "$dep"; then
    echo "  ✅ $dep"
  elif [ -n "$main_ledger" ] && printf '%s\n' "$main_ledger" | grep -qx "$dep"; then
    echo "  ❌ $dep is merged on main, but not in your branch yet"
    stale+=("$dep")
  else
    echo "  ❌ $dep is not merged yet"
    missing+=("$dep")
  fi
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Dependencies of $id"
    echo
    if [ "${#missing[@]}${#stale[@]}" = "00" ]; then echo "**👍 All merged:** ${uniq_deps[*]}"
    else echo "**👎 Waiting on:** ${missing[*]} ${stale[*]}"; fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [ "${#stale[@]}" -gt 0 ]; then
  echo
  echo "❌ ${stale[*]} is merged on main but not in your branch. Run: git fetch origin && git merge origin/main"
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "❌ $id needs ${missing[*]} merged into main first. Build a milestone whose dependencies are all merged (see the schedule in docs/overview.md), or wait for the \"is ready\" issue that names you."
fi
[ "${#stale[@]}${#missing[@]}" = "00" ] || exit 1
echo "👍 Every dependency of $id is merged."
