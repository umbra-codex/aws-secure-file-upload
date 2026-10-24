#!/usr/bin/env bash
# Follows the check GitHub ran for the commit you pushed, and prints one screen.
#
#   scripts/remote-check.sh              the milestone your branch points at (a1-buckets -> A1)
#   scripts/remote-check.sh A1           a specific milestone
#   scripts/remote-check.sh --explain    the same, plus the failed step's raw output
#   scripts/remote-check.sh --summarize A1 < log.txt    the summary alone, from a saved log
#
# You rarely need this: every `git push` already runs the check, and the briefs
# ask for one look here before you mark the pull request ready. It reads the run
# your push started, waits for it to appear, and only starts a run itself when
# that commit has none. GitHub checks what you have PUSHED, so uncommitted work
# is invisible here.
# Needs the GitHub CLI (https://cli.github.com), signed in with `gh auth login`.
set -uo pipefail
cd "$(dirname "$0")/.."

GH=${GH:-gh}
POLLS=${POLLS:-15}          # 15 x 2 s: how long to wait for the push's run to appear
POLL_SLEEP=${POLL_SLEEP:-2}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

usage() {
  cat <<'EOF'
Usage: scripts/remote-check.sh [milestone] [--explain]
       scripts/remote-check.sh --summarize <milestone>   (reads a saved log on stdin)
EOF
}

# Lets the summary be tested without GitHub: scripts/remote-check.sh --summarize A1 < log.txt
if [ "${1:-}" = "--summarize" ]; then
  exec bash scripts/why.sh --summary "$(upper "${2:-}")"
fi

target=""
explain=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --explain) explain=1 ;;
    -*) echo "❌ scripts/remote-check.sh: unknown option $arg"; usage; exit 2 ;;
    *) target=$(upper "$arg") ;;
  esac
done

command -v "$GH" >/dev/null 2>&1 || { echo "❌ Install the GitHub CLI first: https://cli.github.com"; exit 1; }

# One preflight before anything is claimed about runs: a signed-out CLI cannot
# answer a single question here, and polling for 30 s would end in a wrong
# explanation of why nothing came back.
if ! auth_out=$("$GH" auth status 2>&1); then
  echo "❌ The GitHub CLI can't reach your account, so nothing was checked:"
  printf '%s\n' "$auth_out" | sed 's/^/   /'
  case "$auth_out" in
    *"gh auth login"*) ;;
    *) echo "   Run: gh auth login" ;;
  esac
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [ -z "$branch" ] || ! git rev-parse "@{u}" >/dev/null 2>&1; then
  echo "❌ ${branch:-This branch} isn't on GitHub yet. Push it first: git push -u origin <branch>"
  exit 1
fi
[ -n "$(git status --porcelain)" ] && echo "⚠️  You have uncommitted changes. GitHub only checks what you've pushed."

pushed=$(git rev-parse "@{u}")
if [ "$(git rev-parse HEAD)" != "$pushed" ]; then
  echo "⚠️  You have commits that aren't pushed. GitHub checks $(git rev-parse --short "$pushed"), so this result won't include them."
fi

if [ -z "$target" ]; then
  target=$(upper "$(printf '%s' "$branch" | sed -nE 's/^([a-dA-D][0-9]|[mM]0|[iI][nN][tT]|[sS][hH][iI][pP])([-_].*)?$/\1/p')")
fi
if [ -z "$target" ]; then
  echo "❌ Can't tell the milestone from the branch name \"$branch\". Run: scripts/remote-check.sh A1"
  exit 1
fi

# The run for this exact commit, if GitHub has created it. No --event filter:
# the run a push starts is a "push" run, and filtering on workflow_dispatch was
# why this script never saw it and started a second one instead.
list_err=$(mktemp "${TMPDIR:-/tmp}/remote-check-gh.XXXXXX") || exit 1
trap 'rm -f "$list_err"' EXIT

run_for_commit() {
  "$GH" run list --workflow ci.yml --branch "$branch" --commit "$pushed" --limit 5 \
    --json databaseId,headSha --jq '.[0].databaseId // empty' 2> "$list_err"
}

# 0 a run was found (printed), 1 none appeared in time, 2 GitHub could not be asked.
wait_for_run() {
  local attempt=0 found=""
  while [ "$attempt" -lt "$POLLS" ]; do
    if ! found=$(run_for_commit); then return 2; fi
    [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    attempt=$((attempt + 1))
    sleep "$POLL_SLEEP"
  done
  return 1
}

echo "Checking the last commit you pushed to $branch ($(git rev-parse --short "$pushed"))"

echo "Looking for the run your push started..."
run=$(wait_for_run)
run_status=$?
if [ "$run_status" -eq 2 ]; then
  echo "❌ Couldn't ask GitHub for the run, so nothing was checked:"
  sed 's/^/   /' "$list_err"
  exit 1
fi

if [ -z "$run" ]; then
  # Only when this commit has no run at all: a push that started nothing, or a
  # branch whose run has aged out of the list.
  echo "None for this commit yet, so starting one..."
  if ! out=$("$GH" workflow run ci.yml --ref "$branch" -f milestone="$target" 2>&1); then
    echo "❌ Couldn't start the run:"; echo "$out"
    exit 1
  fi
  run=$(wait_for_run)
  run_status=$?
  if [ "$run_status" -eq 2 ]; then
    echo "❌ Couldn't ask GitHub for the run it just started:"
    sed 's/^/   /' "$list_err"
    exit 1
  fi
fi

if [ -z "$run" ]; then
  echo "❌ No run appeared for this commit. Open the repo's Actions tab to see what GitHub has."
  exit 1
fi

start=$SECONDS
"$GH" run watch "$run" --exit-status >/dev/null 2>&1
status=$?
echo "Run finished in $((SECONDS - start))s"

log=$(mktemp "${TMPDIR:-/tmp}/remote-check.XXXXXX") || exit 1
if ! "$GH" run view "$run" --log > "$log" 2>/dev/null; then
  echo "❌ Couldn't download the run's log. Open it on GitHub: $("$GH" run view "$run" --json url --jq .url 2>/dev/null)"
  rm -f "$log"
  exit 1
fi

echo
export WHY_EXPLAIN_CMD="scripts/remote-check.sh --explain"
bash scripts/why.sh --summary "$target" < "$log"

# A gate can fail before any step runs, and a run can die before the check
# prints anything at all: ask for the first thing to fix, not for a step.
if [ "$explain" -eq 1 ]; then
  bash scripts/why.sh --first "$target" --explain < "$log"
else
  bash scripts/why.sh --first "$target" < "$log"
fi
rm -f "$log"

echo
echo "Full results: $("$GH" run view "$run" --json url --jq .url 2>/dev/null)"
exit "$status"
