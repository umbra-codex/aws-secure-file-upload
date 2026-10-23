#!/usr/bin/env bash
# Runs every script test. They are offline and deterministic: a saved GitHub run
# for the summary and the pointer, a tree that is pre-A1 for the local check, and
# a fake gh for the remote one.
#
#   bash tests/scripts/run.sh
#
# Passes, failures and skips are counted separately and printed at the end, so a
# skipped file can never be read as a measured pass. None of this touches the
# milestone tests in tests/*.tftest.hcl, and check.sh never looks in this folder.
set -uo pipefail
cd "$(dirname "$0")/../.."

allow_skips=0
case "${1:-}" in
  --allow-skips) allow_skips=1 ;;
  "") ;;
  *) echo "usage: bash tests/scripts/run.sh [--allow-skips]"; exit 2 ;;
esac

passed=0
failed=0
skipped=0
broken=0

for test in tests/scripts/*.test.sh; do
  echo "== $test"
  out=$(bash "$test" 2>&1)
  status=$?
  printf '%s\n' "$out"

  p=$(printf '%s\n' "$out" | sed -nE 's/.*: ([0-9]+) passed, ([0-9]+) failed.*/\1/p' | tail -1)
  f=$(printf '%s\n' "$out" | sed -nE 's/.*: ([0-9]+) passed, ([0-9]+) failed.*/\2/p' | tail -1)

  if [ -z "$p" ] || [ -z "$f" ]; then
    echo "  (no counts printed; counted as broken)"
    broken=$((broken + 1))
  else
    passed=$((passed + p))
    failed=$((failed + f))
  fi
  if printf '%s\n' "$out" | grep -q '^  SKIP'; then
    skipped=$((skipped + 1))
  fi
  if [ "$status" -ne 0 ]; then
    failed=$((failed + 1))
  fi
done

echo
echo "totals: $passed passed, $failed failed, $skipped skipped file(s)"

if [ "$failed" -gt 0 ] || [ "$broken" -gt 0 ]; then
  echo "👎 failures above"
  exit 1
fi
if [ "$skipped" -gt 0 ]; then
  if [ "$allow_skips" -eq 1 ]; then
    echo "👍 what ran passed; $skipped file(s) skipped their assertions and --allow-skips was given"
    exit 0
  fi
  echo "👎 $skipped file(s) skipped their assertions, so this gate did not measure them"
  echo "   Run with --allow-skips only on a machine that cannot install providers."
  exit 1
fi
echo "👍 every script test passed and every assertion ran"
exit 0
