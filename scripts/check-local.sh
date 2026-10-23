#!/usr/bin/env bash
# Runs the same milestone check CI runs, on your machine, and prints one screen.
#
#   scripts/check-local.sh              the milestone your branch name points at (a1-buckets -> A1)
#   scripts/check-local.sh A1           a specific milestone
#   scripts/check-local.sh --explain    the same, plus every line the check printed
#
# No AWS account and no push: the check's tests use a mocked provider. It runs
# .github/scripts/check.sh itself, so it cannot drift from CI, and it keeps the
# check's working files in .terraform-check/ so your own .terraform/ is left
# alone. GitHub is still the authority: this is a preview of the same check.
set -uo pipefail
cd "$(dirname "$0")/.."

PIN="1.16.6"
PIN_TFLINT="0.64.0"
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

usage() {
  cat <<'EOF'
Usage: scripts/check-local.sh [milestone] [--explain]
  milestone   defaults to the one your branch name points at (a1-buckets -> A1)
  --explain   also print every line the check printed
EOF
}

target=""
explain=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --explain) explain=1 ;;
    -*) echo "❌ scripts/check-local.sh: unknown option $arg"; usage; exit 2 ;;
    *) target=$(upper "$arg") ;;
  esac
done

# --- guards: each one is a way a green run here can still be red on GitHub ---
if [ -z "${TF:-}" ]; then
  if command -v terraform >/dev/null 2>&1; then TF=terraform
  elif command -v tofu >/dev/null 2>&1; then TF=tofu
  else
    echo "❌ Neither terraform nor tofu is on your PATH. Install Terraform $PIN (see your milestone brief, \"What you need installed\")."
    exit 1
  fi
fi
export TF

version=$("$TF" version 2>/dev/null | head -1 | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
echo "Checking with $("$TF" version 2>/dev/null | head -1)"
if [ -n "$version" ] && [ "$version" != "$PIN" ]; then
  echo "⚠️  $TF is $version; CI pins $PIN. A result here can differ from GitHub's. Install $PIN to match."
fi

if [ -z "$target" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  target=$(upper "$(printf '%s' "$branch" | sed -nE 's/^([a-dA-D][0-9]|[mM]0|[iI][nN][tT])([-_].*)?$/\1/p')")
  if [ -z "$target" ]; then
    echo "❌ Can't tell the milestone from the branch name \"${branch:-$(pwd)}\". Run: scripts/check-local.sh A1"
    exit 2
  fi
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "⚠️  You have uncommitted changes. This checks your working tree; GitHub checks commits, so commit before you trust a green run there."
fi

# The dependency gate is a separate CI step, and the spec tests are mocked, so
# without this a missing dependency looks green here and red on GitHub. CI runs
# it only for INT and the A-D milestones (ci.yml), so M0 does not get a warning
# about a gate that never applies to it.
deps_bad=0
deps_msg=""
deps_wanted=0
case "$target" in
  INT|[A-D][0-9]) deps_wanted=1 ;;
esac
if [ "$deps_wanted" -eq 1 ] && [ -f "docs/milestones/$target.md" ] && [ -f .github/scripts/deps.sh ]; then
  deps_out=$(bash .github/scripts/deps.sh "$target" 2>&1)
  deps_status=$?
  case "$deps_status" in
    0) printf '%s\n' "$deps_out" ;;
    *) echo "⚠️  The dependency gate CI runs first would fail:"
       printf '%s\n' "$deps_out" | sed 's/^/     /'
       deps_bad=1
       deps_msg=$(printf '%s\n' "$deps_out" | grep -v '^[[:space:]]*$' | head -1 | sed 's/^ *//') ;;
  esac
fi

# tflint is a separate CI step too. Run it when it is installed.
lint_bad=0
lint_log=$(mktemp "${TMPDIR:-/tmp}/check-local-tflint.XXXXXX") || exit 1
if command -v tflint >/dev/null 2>&1; then
  echo "Running tflint (CI runs it as its own step)..."
  lint_version=$(tflint --version 2>/dev/null | sed -nE 's/^TFLint version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1)
  if [ -n "$lint_version" ] && [ "$lint_version" != "$PIN_TFLINT" ]; then
    echo "⚠️  tflint is $lint_version; CI pins $PIN_TFLINT. This step can differ from GitHub's."
  fi
  if ! tflint --init > "$lint_log" 2>&1; then
    echo "⚠️  tflint could not fetch its plugins (that needs network), so it was skipped here. CI still runs it."
  elif tflint --recursive --config "$(pwd)/.tflint.hcl" >> "$lint_log" 2>&1; then
    echo "  ✅ tflint"
  else
    echo "  ❌ tflint"
    sed 's/^/     /' "$lint_log" | tail -n 20
    lint_bad=1
    lint_msg=$(grep -v '^[[:space:]]*$' "$lint_log" | head -1 | sed 's/^ *//')
  fi
else
  echo "⚠️  tflint isn't installed. CI runs it as its own step, so a green run here can still be red there."
fi
rm -f "$lint_log"

# --- the check itself: the same file CI runs, with its working files moved ---
log=$(mktemp "${TMPDIR:-/tmp}/check-local.XXXXXX") || exit 1
echo
echo "Running .github/scripts/check.sh $target all (about 20 seconds)..."
TF_DATA_DIR=.terraform-check bash .github/scripts/check.sh "$target" all > "$log" 2>&1
status=$?

# A gate that runs before check.sh (the dependency gate, tflint) can be red while
# every step passes. Then the summary must not print a pass, and the Next line
# must be the gate's own message, in the order CI runs them.
lint_msg=${lint_msg:-}
if [ "$deps_bad" -eq 1 ]; then
  WHY_LOCAL_GATE="dependency gate"
  WHY_LOCAL_MSG=$deps_msg
elif [ "$lint_bad" -eq 1 ]; then
  WHY_LOCAL_GATE="tflint"
  WHY_LOCAL_MSG=$lint_msg
fi
if [ -n "${WHY_LOCAL_GATE:-}" ]; then
  export WHY_LOCAL_GATE WHY_LOCAL_MSG
  export WHY_NO_PASS=1
fi

echo
bash scripts/why.sh --summary "$target" < "$log"

# A gate can fail before any step runs, and a run can die before the check
# prints anything at all, so ask for the first thing to fix rather than for a
# first failed step.
bash scripts/why.sh --first "$target" < "$log"

if [ "$explain" -eq 1 ]; then
  echo
  echo "Full check output:"
  cat "$log"
fi
rm -f "$log"

echo
echo "GitHub is the authority. This run is a preview: the push you make next runs the same check on GitHub,"
echo "and \"scripts/remote-check.sh\" follows that run and prints the same summary."

if [ "$status" -ne 0 ] || [ "$lint_bad" -ne 0 ] || [ "$deps_bad" -ne 0 ]; then exit 1; fi
exit 0
