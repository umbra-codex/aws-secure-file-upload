#!/usr/bin/env bash
# The milestone check that CI runs on every push. On your machine, run it through
# scripts/check-local.sh; scripts/remote-check.sh re-runs it on GitHub.
#
#   .github/scripts/check.sh A1        one milestone (plus fmt and validate)
#   .github/scripts/check.sh all       every milestone listed in milestones.txt
#   .github/scripts/check.sh A1 all    both (what CI runs on an a1-* branch)
#
# Uses terraform (CI pins the version); TF=tofu overrides. The spec tests use a
# mocked AWS provider, so no AWS account or credentials are involved. Results
# also go to the GitHub Actions run summary.
set -uo pipefail
cd "$(dirname "$0")/../.."

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

case "${1:-}" in
  "" | -h | --help)
    echo "Usage: .github/scripts/check.sh <milestone...|all>   e.g. .github/scripts/check.sh A1 all"
    [ -z "${1:-}" ] && exit 2 || exit 0
    ;;
esac

if [ -z "${TF:-}" ]; then
  if command -v terraform >/dev/null 2>&1; then TF=terraform
  elif command -v tofu >/dev/null 2>&1; then TF=tofu
  else echo "❌ Neither terraform nor tofu is on your PATH."; exit 1
  fi
fi

# Expand "all" from milestones.txt and drop duplicates, keeping order.
ids=()
add_id() {
  local id existing
  id=$(upper "$1")
  [ -z "$id" ] && return
  for existing in ${ids[@]+"${ids[@]}"}; do [ "$existing" = "$id" ] && return; done
  ids+=("$id")
}
for arg in "$@"; do
  if [ "$(lower "$arg")" = "all" ]; then
    while IFS= read -r id; do add_id "$id"; done < <(grep -Ev '^[[:space:]]*(#|$)' milestones.txt | tr -d ' \r')
  else
    add_id "$arg"
  fi
done
if [ "${#ids[@]}" -eq 0 ]; then echo "❌ No milestones to check (is milestones.txt empty?)."; exit 1; fi

failed_steps=""
summary_rows=""
failure_log=""
step() {
  local name="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    echo "  ✅ $name"
    summary_rows="$summary_rows| $name | ✅ |
"
  else
    echo "  ❌ $name"
    printf '%s\n' "$out" | sed 's/^/     /'
    failed_steps="$failed_steps
     - $name"
    summary_rows="$summary_rows| $name | ❌ |
"
    failure_log="$failure_log
### $name
\`\`\`
$out
\`\`\`
"
  fi
}

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "## Milestone check: ${ids[*]}"
    echo
    echo "| Step | Result |"
    echo "|---|---|"
    printf '%s' "$summary_rows"
    echo
    if [ -z "$failed_steps" ]; then
      echo "**👍 Passed.**"
    else
      echo "**👎 Failed.** Fix the first ❌ above, commit, and push. The check runs again on every push."
      echo
      echo "<details><summary>Output of the failed steps</summary>"
      printf '%s\n' "$failure_log"
      echo "</details>"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
}

finish() {
  write_summary
  if [ -z "$failed_steps" ]; then
    echo "👍 ${ids[*]} passed."
    exit 0
  fi
  echo "👎 Failed:$failed_steps"
  echo "   Fix the first one listed, commit, and push. The check runs again on every push."
  exit 1
}

echo "Checking ${ids[*]} with $("$TF" version | head -1)"
step "formatting (fmt -check)" "$TF" fmt -check -recursive
step "init" "$TF" init -backend=false -input=false
step "validate" "$TF" validate -no-color

# Spec tests can't run on a config that doesn't init or validate; stop here
# so the real problem isn't buried under follow-on errors.
case "$failed_steps" in *init* | *validate*) finish ;; esac

# A file check (*.check): each line is "path | regex | message". The file
# must exist and contain a match for the regex.
run_file_check() {
  local check_file="$1" out="" line path rest regex msg
  while IFS= read -r line; do
    case "$line" in "" | "#"*) continue ;; esac
    # Split at the first and the last " | ", so the regex itself may contain "|".
    path=${line%% | *}
    rest=${line#* | }
    msg=${rest##* | }
    regex=${rest% | *}
    if [ ! -f "$path" ]; then
      case "$out" in *"$path is missing"*) ;; *) out="$out$path is missing
" ;; esac
    elif ! grep -Eq -- "$regex" "$path"; then
      out="$out$path $msg
"
    fi
  done < "$check_file"
  [ -z "$out" ] && return 0
  printf '%s' "$out"
  return 1
}

# A milestone's steps are tests/<id>.tftest.hcl, or tests/<id>-<n>-<name>.tftest.hcl
# and tests/<id>-<n>-<name>.check, run in step order.
for id in "${ids[@]}"; do
  lid=$(lower "$id")
  found=0
  for file in tests/"$lid".tftest.hcl tests/"$lid"-*; do
    [ -f "$file" ] || continue
    found=1
    base=$(basename "$file")
    case "$base" in
      "$lid".tftest.hcl) label="$id spec" ;;
      *) rest=${base#"$lid"-}; num=${rest%%-*}; name=${rest#*-}; name=${name%.tftest.hcl}; name=${name%.check}
         label="$id step $num ($name)" ;;
    esac
    case "$file" in
      *.check) step "$label" run_file_check "$file" ;;
      *) step "$label" "$TF" test -no-color -filter="$file" ;;
    esac
  done
  if [ "$found" -eq 0 ]; then
    echo "  ❌ $id: no test files in tests/"
    failed_steps="$failed_steps
     - $id (no test files)"
    summary_rows="$summary_rows| $id | ❌ no test files |
"
  fi
done

finish
