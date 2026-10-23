#!/usr/bin/env bash
# The regression fixture: on a tree where no A1 step is built yet, the local
# check must say so, mark step 1 as next, and point at the right part of the
# brief. Offline and real: it runs the same check CI runs, on a copy.
#
#   bash tests/scripts/check-local.test.sh
#
# It needs terraform or tofu. If this machine cannot install providers (no
# network and no mirror), the test says so and passes, because there is nothing
# to measure; the assertions run wherever the provider is available.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tests/scripts/lib.sh

root=$(pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-local.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/repo"
( cd "$root" && tar cf - --exclude ./.git --exclude ./.terraform-check . ) | ( cd "$tmp/repo" && tar xf - ) || {
  echo "❌ could not copy the tree"
  exit 1
}

# --explain, so the check's own lines are in the output: the offline skip below
# has to judge the provider error itself, not a summary of it.
out=$( cd "$tmp/repo" && bash scripts/check-local.sh A1 --explain 2>&1 )
status=$?

case "$out" in
  *"Failed to install provider"*|*"Failed to query available provider packages"*)
    echo "  SKIP: providers could not be installed (offline, and no TF_CLI_CONFIG_FILE mirror)."
    echo "  Nothing was measured, so no assertion is claimed."
    exit 0
    ;;
esac

has "A1: 0 of 5 steps done" "$out" "the summary says 0 of 5"
has "❌ step 1 (variables)      <- next" "$out" "step 1 is marked next"
has '### variables.tf' "$out" "the pointer names the brief section"
has "items 1 to 4" "$out" "the pointer names the item numbers"
has "GitHub is the authority" "$out" "every run says GitHub is the authority"
has "check.sh" "$out" "it names the check it ran"

if [ "$status" -eq 1 ]; then ok "a red run exits 1"; else no "a red run exits 1" "got $status"; fi

# A red gate that runs before check.sh must not end on a pass line: the verdict
# line is the one thing the learner reads. Both stubs are written here so this
# costs no time and needs no provider.
printf '#!/usr/bin/env bash\necho "  ✅ formatting (fmt -check)"\necho "  ✅ init"\necho "  ✅ validate"\necho "  ✅ A1 step 1 (variables)"\necho "👍 A1 passed."\n' > "$tmp/repo/.github/scripts/check.sh"
printf '#!/usr/bin/env bash\necho "❌ A1 is not merged yet (stub dependency gate)"\nexit 1\n' > "$tmp/repo/.github/scripts/deps.sh"

out_deps=$( cd "$tmp/repo" && bash scripts/check-local.sh A1 2>&1 )
st_deps=$?
hasnt "👍 A1 passed." "$out_deps" "a red dependency gate is not reported as a pass"
has "stopped at the dependency gate" "$out_deps" "the next line names the dependency gate"
has "A1 is not merged yet" "$out_deps" "the gate's own message is printed"
if [ "$st_deps" -eq 1 ]; then ok "a red dependency gate exits 1"; else no "a red dependency gate exits 1" "got $st_deps"; fi

# M0 has no 'Depends on' row, and ci.yml does not run that gate for M0, so a
# local run must not warn about it.
out_m0=$( cd "$tmp/repo" && bash scripts/check-local.sh M0 2>&1 )
hasnt "dependency gate" "$out_m0" "M0 gets no dependency-gate warning"
hasnt "is not merged yet" "$out_m0" "M0 does not run the dependency gate"

report check-local
