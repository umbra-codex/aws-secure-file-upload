#!/usr/bin/env bash
# The ship check's own tests: every rule must catch its own kind of leftover, and
# a clean tree must pass. Offline, and it never reads the real repository, so it
# says the same thing before the removal and after it.
#
#   bash tests/scripts/ship-check.test.sh
#
# Each case builds a small tree in a temporary folder, because the check takes a
# directory and the point is what it finds there.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tests/scripts/lib.sh

root=$(pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ship-check.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# A tree with nothing to find: the five anchors, and one sentence each.
clean() { # $1 folder
  mkdir -p "$1/docs" "$1/evidence" "$1/tests"
  printf '# Demo pipeline\n\nIt takes a file and stores it.\n' > "$1/README.md"
  printf '# Architecture\n\nThe flow.\n' > "$1/docs/architecture.md"
  printf '# Decisions\n\n| Date | Decision | Why |\n|---|---|---|\n| 2026-01-02 | none | nothing yet |\n' > "$1/docs/decisions.md"
  printf 'MIT License\n\nCopyright (c) 2026 the team\n' > "$1/LICENSE"
  printf '# Evidence\n\n| Test | Result |\n|---|---|\n| clean file | APPROVED |\n' > "$1/evidence/README.md"
}

run() { # $1 folder; prints the check's output, returns its exit status
  ( cd "$root" && bash scripts/ship-check.sh "$1" 2>&1 )
}

# 1. A clean tree passes, with one line.
clean "$tmp/good"
out=$(run "$tmp/good"); st=$?
has "SHIP: clean." "$out" "a clean tree prints the pass line"
hasnt "problem" "$out" "a clean tree prints no count"
if [ "$st" -eq 0 ]; then ok "a clean tree exits 0"; else no "a clean tree exits 0" "got $st"; fi

# 2. Scaffolding, by path.
cp -a "$tmp/good" "$tmp/brief"
mkdir -p "$tmp/brief/docs/milestones"
printf '# A1: build it\n' > "$tmp/brief/docs/milestones/A1.md"
out=$(run "$tmp/brief"); st=$?
has "scaffolding: docs/milestones" "$out" "a brief folder is reported as scaffolding"
if [ "$st" -eq 1 ]; then ok "a red tree exits 1"; else no "a red tree exits 1" "got $st"; fi

# 3. A grader: a text check, and a spec test that names its brief.
cp -a "$tmp/good" "$tmp/grader"
printf 'README.md | ^# | needs a title\n' > "$tmp/grader/tests/a1-1-title.check"
out=$(run "$tmp/grader")
has "grader: tests/a1-1-title.check (a text check)" "$out" "a text check is reported as a grader"
cp -a "$tmp/good" "$tmp/grader2"
printf '# A1 step 1: the bucket\n\nmock_provider "aws" {\n}\n' > "$tmp/grader2/tests/a1-1-bucket.tftest.hcl"
out=$(run "$tmp/grader2")
has "grader: tests/a1-1-bucket.tftest.hcl (names its brief or a step)" "$out" "a step spec test is reported as a grader"

# 4. The three phrases, the other learner words, and a milestone ID.
cp -a "$tmp/good" "$tmp/phrase"
printf '# Demo pipeline\n\nCheckpoint: paste this.\n' > "$tmp/phrase/README.md"
out=$(run "$tmp/phrase")
has "learner text: README.md" "$out" "a checkpoint heading is reported"
cp -a "$tmp/good" "$tmp/phrase2"
printf '# Decisions\n\nDone when the table is full.\n' > "$tmp/phrase2/docs/decisions.md"
out=$(run "$tmp/phrase2")
has "learner text: docs/decisions.md" "$out" "a done-when sentence is reported"
cp -a "$tmp/good" "$tmp/phrase3"
printf '# Evidence\n\nHere you will paste the output.\n' > "$tmp/phrase3/evidence/README.md"
out=$(run "$tmp/phrase3")
has "learner text: evidence/README.md" "$out" "a sentence addressed to a learner is reported"
cp -a "$tmp/good" "$tmp/phrase4"
printf '# Architecture\n\nBuilt in B2.\n' > "$tmp/phrase4/docs/architecture.md"
out=$(run "$tmp/phrase4")
has "learner text: docs/architecture.md" "$out" "a milestone ID is reported"

# 5. A local path.
cp -a "$tmp/good" "$tmp/path"
printf '# Demo pipeline\n\nCopy it from ~/Projects/group/demo.\n' > "$tmp/path/README.md"
out=$(run "$tmp/path")
has "local path: README.md" "$out" "a home-folder path is reported"

# 6. A secret-looking string. Built from pieces so this file does not contain one.
cp -a "$tmp/good" "$tmp/secret"
printf '# Demo pipeline\n\nAKIA%s\n' "ABCDEFGHIJKLMNOP" > "$tmp/secret/README.md"
out=$(run "$tmp/secret")
has "secret: README.md" "$out" "an access key ID shape is reported"

# 7. A loose end.
cp -a "$tmp/good" "$tmp/todo"
printf '# Architecture\n\nTODO: describe the retry.\n' > "$tmp/todo/docs/architecture.md"
out=$(run "$tmp/todo")
has "loose end: docs/architecture.md" "$out" "a TODO is reported"

# 8. A missing anchor: a repository with no license, and one with no README.
cp -a "$tmp/good" "$tmp/nolicense"
rm "$tmp/nolicense/LICENSE"
out=$(run "$tmp/nolicense")
has "missing: LICENSE" "$out" "a missing license is reported"
cp -a "$tmp/good" "$tmp/noreadme"
rm "$tmp/noreadme/README.md"
out=$(run "$tmp/noreadme")
has "missing: README.md" "$out" "a missing README is reported"

# 9. The build machinery is skipped while it is still there: the last commit of
# the milestone removes it, and the check cannot ask for what it is about to lose.
cp -a "$tmp/good" "$tmp/machinery"
mkdir -p "$tmp/machinery/scripts" "$tmp/machinery/.github/scripts"
printf '# Done when you push\n' > "$tmp/machinery/scripts/check-local.sh"
printf '# Checkpoint counting\n' > "$tmp/machinery/.github/scripts/check.sh"
out=$(run "$tmp/machinery"); st=$?
has "SHIP: clean." "$out" "the build machinery is not read"
if [ "$st" -eq 0 ]; then ok "a tree with only the machinery in it exits 0"; else no "a tree with only the machinery in it exits 0" "got $st"; fi

# 10. Usage: a second argument is a mistake, not a second tree.
out=$( bash scripts/ship-check.sh "$tmp/good" "$tmp/good" 2>&1 ); st=$?
has "too many arguments" "$out" "a second argument is refused"
if [ "$st" -eq 2 ]; then ok "a usage mistake exits 2"; else no "a usage mistake exits 2" "got $st"; fi

# 11. With no argument it reads the repository it is in. This says nothing about
# whether that repository is clean, which changes during the milestone.
out=$( cd "$root" && bash scripts/ship-check.sh 2>&1 ); st=$?
has "SHIP:" "$out" "with no argument it reads its own repository"
case "$st" in 0|1) ok "with no argument it exits 0 or 1, never 2" ;; *) no "with no argument it exits 0 or 1, never 2" "got $st" ;; esac

report ship-check
