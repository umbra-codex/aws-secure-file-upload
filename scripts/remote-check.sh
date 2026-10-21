#!/usr/bin/env bash
# Re-runs the milestone check on GitHub for your pushed branch and prints your progress.
#
#   scripts/remote-check.sh       check the milestone your branch points at (a1-buckets -> A1)
#   scripts/remote-check.sh A1    check a specific milestone
#
# You usually don't need this: every `git push` already runs the check. Use it
# to re-run without pushing. GitHub checks what you have PUSHED, not local edits.
# Nothing is saved on your machine; the results stay on GitHub.
# Needs the GitHub CLI (https://cli.github.com), signed in with `gh auth login`.
set -uo pipefail
cd "$(dirname "$0")/.."

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# Reads the "Milestone checks" output of a finished run on stdin and prints a
# progress summary for one milestone.
summarize() {
  local target="$1" rows line name mark
  local gates_ok=1 done=0 total=0 next="" earlier="" earlier_bad="" steps=""
  rows=$(grep -E '^  (✅|❌) ' || true)
  while IFS= read -r line; do
    case "$line" in
      "  ✅ "*) mark="✅"; name=${line#"  ✅ "} ;;
      "  ❌ "*) mark="❌"; name=${line#"  ❌ "} ;;
      *) continue ;;
    esac
    case "$name" in
      "formatting (fmt -check)" | init | validate)
        [ "$mark" = "✅" ] || gates_ok=0 ;;
      "$target step "* | "$target spec" | "$target: "*)
        total=$((total + 1))
        if [ "$mark" = "✅" ]; then
          done=$((done + 1)); steps="$steps  ✅ ${name#"$target "}
"
        else
          if [ -z "$next" ]; then next=${name#"$target "}; steps="$steps  ❌ ${name#"$target "}      <- next
"
          else steps="$steps  ❌ ${name#"$target "}
"; fi
        fi ;;
      *)
        id=${name%% *}; id=${id%:}
        case " $earlier " in *" $id "*) ;; *) earlier="$earlier $id" ;; esac
        [ "$mark" = "✅" ] || case " $earlier_bad " in *" $id "*) ;; *) earlier_bad="$earlier_bad $id" ;; esac ;;
    esac
  done <<< "$rows"

  echo
  echo "$target progress: $done of $total steps done"
  if [ "$gates_ok" -eq 1 ]; then echo "  ✅ formatting, init, validate"; else echo "  ❌ formatting, init, or validate (fix this first; open the results page for details)"; fi
  printf '%s' "$steps"
  if [ -n "$earlier" ]; then
    if [ -z "$earlier_bad" ]; then echo "  ✅ earlier milestones still pass ($(echo $earlier | sed 's/ /, /g'))"
    else echo "  ❌ earlier milestones broken:$(echo $earlier_bad | sed 's/^/ /; s/ /, /g; s/^, / /')"; fi
  fi
  echo
  if [ "$gates_ok" -eq 1 ] && [ "$done" -eq "$total" ] && [ "$total" -gt 0 ] && [ -z "$earlier_bad" ]; then
    echo "👍 $target passed. Next: run \"Done when\" in your own AWS account."
  elif [ -n "$next" ]; then
    echo "Next: fix $target $next, then commit and push."
  else
    echo "Next: fix the ❌ line above, then commit and push."
  fi
}

# Lets the summary be tested without GitHub: scripts/remote-check.sh --summarize A1 < log.txt
if [ "${1:-}" = "--summarize" ]; then summarize "$(upper "$2")"; exit 0; fi

command -v gh >/dev/null 2>&1 || { echo "❌ Install the GitHub CLI first: https://cli.github.com"; exit 1; }

branch=$(git rev-parse --abbrev-ref HEAD)
if ! git rev-parse "@{u}" >/dev/null 2>&1; then
  echo "❌ $branch isn't on GitHub yet. Push it first: git push -u origin $branch"
  exit 1
fi
[ -n "$(git status --porcelain)" ] && echo "⚠️  You have uncommitted changes. GitHub only checks what you've pushed."
[ "$(git rev-parse HEAD)" != "$(git rev-parse "@{u}")" ] && echo "⚠️  You have commits that aren't pushed. Run git push to include them."

target=$(upper "${1:-}")
if [ -z "$target" ]; then
  target=$(upper "$(printf '%s' "$branch" | sed -nE 's/^([a-dA-D][0-9]|[mM]0|[iI][nN][tT])([-_].*)?$/\1/p')")
fi
if [ -z "$target" ]; then
  echo "❌ Can't tell the milestone from the branch name \"$branch\". Run: scripts/remote-check.sh A1"
  exit 1
fi

latest_run() {
  gh run list --workflow ci.yml --branch "$branch" --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty'
}

echo "Checking the last commit you pushed to $branch ($(git rev-parse --short "@{u}"))"
before=$(latest_run)
gh workflow run ci.yml --ref "$branch" -f milestone="$target" || exit 1

echo "Waiting for GitHub to start the run..."
run=""
for _ in $(seq 1 30); do
  run=$(latest_run)
  [ -n "$run" ] && [ "$run" != "$before" ] && break
  run=""
  sleep 2
done
if [ -z "$run" ]; then
  echo "❌ The run didn't appear within a minute. Check the repo's Actions tab."
  exit 1
fi

start=$SECONDS
gh run watch "$run" --exit-status >/dev/null 2>&1
status=$?
echo "Run finished in $((SECONDS - start))s"

gh run view "$run" --log 2>/dev/null \
  | awk -F'\t' '$2 == "Milestone checks" { print $3 }' \
  | sed -E 's/^[0-9T:.Z-]+ //' \
  | summarize "$target"

echo
echo "Full results: $(gh run view "$run" --json url --jq .url)"
exit $status
