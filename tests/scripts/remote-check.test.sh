#!/usr/bin/env bash
# remote-check.sh against a fake gh and a throwaway repository, so the two
# defects stay fixed: it must follow the run the push started, and it must not
# start (and so cancel) another one.
#
#   bash tests/scripts/remote-check.test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tests/scripts/lib.sh

root=$(pwd)
command -v git >/dev/null 2>&1 || { echo "  SKIP: git is not installed"; exit 0; }
[ -f tests/fixtures/sample-log.txt ] || { echo "❌ missing tests/fixtures/sample-log.txt"; exit 1; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/remote-check.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

work="$tmp/repo"
mkdir -p "$work/docs" "$work/tests"
cp -a scripts "$work/scripts"
cp -a docs/milestones "$work/docs/milestones"
cp -a tests/fixtures "$work/tests/fixtures"
cp -a tests/scripts "$work/tests/scripts"
chmod +x "$work/scripts/"*.sh "$work/tests/scripts/fake-gh/gh"

( cd "$work" \
  && git init -q . \
  && git symbolic-ref HEAD refs/heads/a1-buckets \
  && git add -A \
  && git -c user.email=test@example.com -c user.name=test commit -qm "feat(a1): a tree for the test" \
  && git init -q --bare "$tmp/origin.git" \
  && git remote add origin "$tmp/origin.git" \
  && git push -q -u origin a1-buckets ) || { echo "❌ could not build the throwaway repository"; exit 1; }

sha=$( cd "$work" && git rev-parse HEAD )
fake="$work/tests/scripts/fake-gh/gh"

state() { # $1 = file, rest = the JSON body
  cat > "$1" <<JSON
{
  "head_sha": "$sha",
  "run_id": "$2",
  "run_url": "$3",
  "log": "$root/tests/fixtures/sample-log.txt",
  "conclusion_exit": "$4",
  "visits_before_run_appears": "$5",
  "dispatch_creates_run": "$6",
  "auth_ok": "${7:-yes}",
  "dispatch_run_id": "5151",
  "dispatch_run_url": "https://example.test/run/5151"
}
JSON
}

# 1. A run for this commit already exists: follow it, start nothing.
state "$tmp/state1.json" 4242 "https://example.test/run/4242" 1 0 no
export FAKE_GH_JSON="$tmp/state1.json"
export FAKE_GH_CALLS="$tmp/calls1.txt"
: > "$FAKE_GH_CALLS"
out1=$( cd "$work" && GH="$fake" bash scripts/remote-check.sh 2>&1 )
status1=$?

has "Checking the last commit you pushed to a1-buckets" "$out1" "it names the pushed commit"
has "A1: 1 of 5 steps done" "$out1" "it prints the summary"
has "Next: A1 step 2 (resources)" "$out1" "it prints why for the first red step"
has "Run scripts/remote-check.sh --explain" "$out1" "its hint names a command that exists here"
has "items 5 to 9" "$out1" "the pointer survives the round trip"
has "Full results: https://example.test/run/4242" "$out1" "it reports the run it followed"
hasnt "starting one" "$out1" "it did not start a run of its own"
hasnt "workflow run" "$(cat "$FAKE_GH_CALLS")" "it called no workflow run"
if [ "$status1" -eq 1 ]; then ok "a failed run exits 1"; else no "a failed run exits 1" "got $status1"; fi

# 2. The run appears a couple of polls late: still followed, still no dispatch.
state "$tmp/state2.json" 4343 "https://example.test/run/4343" 0 2 no
rm -f "$tmp/state2.json.list"
export FAKE_GH_JSON="$tmp/state2.json"
export FAKE_GH_CALLS="$tmp/calls2.txt"
: > "$FAKE_GH_CALLS"
out2=$( cd "$work" && GH="$fake" POLL_SLEEP=0 bash scripts/remote-check.sh 2>&1 )
has "Full results: https://example.test/run/4343" "$out2" "it waits for a late run and follows it"
hasnt "workflow run" "$(cat "$FAKE_GH_CALLS")" "waiting for it started nothing"

# 3. No run for this commit at all: dispatch once, then follow that run.
state "$tmp/state3.json" "" "" 0 0 yes
rm -f "$tmp/state3.json.list"
export FAKE_GH_JSON="$tmp/state3.json"
export FAKE_GH_CALLS="$tmp/calls3.txt"
: > "$FAKE_GH_CALLS"
out3=$( cd "$work" && GH="$fake" POLL_SLEEP=0 bash scripts/remote-check.sh 2>&1 )
calls3=$(cat "$FAKE_GH_CALLS")
has "starting one" "$out3" "it says it is starting a run when none exists"
has "workflow run" "$calls3" "it dispatches only in that case"
has "Full results: https://example.test/run/5151" "$out3" "it follows the run it started"

# 4. gh is installed but signed out: say so at once, and claim nothing about runs.
state "$tmp/state4.json" 4242 "https://example.test/run/4242" 1 0 no no
export FAKE_GH_JSON="$tmp/state4.json"
export FAKE_GH_CALLS="$tmp/calls4.txt"
: > "$FAKE_GH_CALLS"
out4=$( cd "$work" && GH="$fake" POLL_SLEEP=0 bash scripts/remote-check.sh 2>&1 )
status4=$?
calls4=$(cat "$FAKE_GH_CALLS")
has "can't reach your account" "$out4" "a signed-out CLI is reported as such"
has "gh auth login" "$out4" "it says how to sign in"
hasnt "None for this commit" "$out4" "it does not blame the commit for a signed-out CLI"
hasnt "Looking for the run" "$out4" "it does not poll before it has an account"
hasnt "workflow run" "$calls4" "it dispatches nothing when signed out"
if [ "$status4" -eq 1 ]; then ok "a signed-out CLI exits 1"; else no "a signed-out CLI exits 1" "got $status4"; fi

report remote-check