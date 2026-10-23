#!/usr/bin/env bash
# Assertions shared by the script tests. Sourced, not run.
pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ✅ %s\n' "$1"; }
no() {
  fail=$((fail + 1))
  printf '  ❌ %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '     %s\n' "$2"; fi
}

# has <needle> <haystack> <what>
has() {
  case "$2" in
    *"$1"*) ok "$3" ;;
    *) no "$3" "expected to find: $1" ;;
  esac
}

# hasnt <needle> <haystack> <what>
hasnt() {
  case "$2" in
    *"$1"*) no "$3" "found what should not be there: $1" ;;
    *) ok "$3" ;;
  esac
}

report() {
  printf '  %s: %s passed, %s failed\n' "${1:-result}" "$pass" "$fail"
  [ "$fail" -eq 0 ]
}
