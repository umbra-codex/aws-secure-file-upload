#!/usr/bin/env bash
# The SHIP check. Fails while the build scaffolding, the text written for a
# learner, a local path, or a secret-looking string is still in the repository.
#
#   scripts/ship-check.sh            the repository this script lives in
#   scripts/ship-check.sh <dir>      another tree, such as a copy
#
# Exit 0 with one line when the tree is clean. Exit 1 with one line per problem,
# then a count: the list is the work, and the same command proves it is done.
# Exit 2 for a usage mistake.
#
# It reads only the text files of the tree, and prints a file and a line number,
# never the line itself, so its output is safe to paste anywhere.
#
# What it skips: .git/, .terraform*/, node_modules/, scripts/, and
# .github/scripts/. The last commit of the milestone deletes the last two, and a
# check cannot ask for the removal of the folder it is running from. Everything
# else in the repository is read, including the workflows.
#
# No bash 4 features: this runs on the learner's machine, which may have bash 3.2.
set -uo pipefail

PROG=ship-check
root=""
if [ "$#" -gt 1 ]; then
  echo "$PROG: too many arguments. Usage: scripts/$PROG.sh [directory]"
  exit 2
fi
case "${1:-}" in
  -h|--help)
    echo "Usage: scripts/$PROG.sh [directory]"
    echo "  directory   the tree to read; the default is the repository this script is in"
    exit 0
    ;;
  "")
    root=$(cd "$(dirname "$0")/.." && pwd) || exit 2
    ;;
  *)
    case "$1" in
      -*) echo "$PROG: unknown option $1"; exit 2 ;;
    esac
    root=$1
    ;;
esac
if [ ! -d "$root" ]; then
  echo "$PROG: $root is not a folder."
  exit 2
fi

problems=0
n_scaffold=0
n_grader=0
n_phrase=0
n_path=0
n_secret=0
n_todo=0
n_missing=0

skipfile=$(mktemp "${TMPDIR:-/tmp}/ship-check.XXXXXX") || exit 2
trap 'rm -f "$skipfile"' EXIT
: > "$skipfile"

report() { # $1 rule, $2 the rest of the line; counts of rules are kept apart
  printf '%s: %s\n' "$1" "$2"
  problems=$((problems + 1))
  case "$1" in
    scaffolding) n_scaffold=$((n_scaffold + 1)) ;;
    grader)      n_grader=$((n_grader + 1)) ;;
    "learner text") n_phrase=$((n_phrase + 1)) ;;
    "local path")   n_path=$((n_path + 1)) ;;
    secret)      n_secret=$((n_secret + 1)) ;;
    "loose end") n_todo=$((n_todo + 1)) ;;
    missing)     n_missing=$((n_missing + 1)) ;;
  esac
}

# A path already reported as scaffolding or as a grader is not searched again for
# learner text: it is leaving whole, and naming it twice only buries the list.
already() { # $1 relative path
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$1" in "$s"|"$s"/*) return 0 ;; esac
  done < "$skipfile"
  return 1
}

# Every file the check reads, one relative path per line.
files() {
  ( cd "$root" || exit 1
    find . -type f 2>/dev/null | sed 's|^\./||' | while IFS= read -r rel; do
      case "$rel" in
        .git/*|.terraform|.terraform/*|.terraform-*|.terraform-*/*|node_modules/*|scripts/*|.github/scripts/*) continue ;;
      esac
      printf '%s\n' "$rel"
    done | sort )
}

# The first lines that match, as line numbers, or nothing. Line numbers only:
# the output can be pasted into a pull request without carrying a file's content.
hits() { # $1 relative path, $2 egrep pattern, $3 "" or -i
  [ -f "$root/$1" ] || return 0
  grep -n $3 -E -e "$2" "$root/$1" 2>/dev/null | sed 's/:.*//' | head -3 | paste -sd, - | sed 's/,/, /g'
}

check() { # $1 rule label, $2 egrep pattern, $3 "" or -i
  local rel line
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    already "$rel" && continue
    line=$(hits "$rel" "$2" "$3")
    [ -n "$line" ] && report "$1" "$rel (line $line)"
  done <<EOF
$(files)
EOF
}

# 1. The scaffolding, by path.
for p in docs/milestones docs/overview.md docs/portions milestones.txt \
         .github/owners.txt .github/CODEOWNERS .github/pull_request_template.md \
         .github/workflows/next.yml tests/scripts tests/fixtures; do
  if [ -e "$root/$p" ]; then
    report scaffolding "$p"
    printf '%s\n' "$p" >> "$skipfile"
  fi
done

# 2. The graders. A text check grades a step by definition; anything else in
# tests/ that still names a brief or a step is a spec test for the build.
if [ -d "$root/tests" ]; then
  while IFS= read -r rel; do
    case "$rel" in
      ""|tests/scripts/*|tests/fixtures/*) continue ;;
    esac
    case "$rel" in
      *.check) report grader "$rel (a text check)"; printf '%s\n' "$rel" >> "$skipfile"; continue ;;
    esac
    if [ -n "$(hits "$rel" 'docs/milestones|Brief:|step [0-9]' '')" ]; then
      report grader "$rel (names its brief or a step)"
      printf '%s\n' "$rel" >> "$skipfile"
    fi
  done <<EOF
$(files | grep '^tests/' || true)
EOF
fi

# 3. The text written for a learner, in any file that stays. Case-insensitive,
# because a sentence can start with the word: what matters is the word. The
# build marker PLACEHOLDER is matched in capitals, the way the notes write it, so
# a value such as "placeholder-router" is not a finding.
check "learner text" 'Checkpoint|Done when|you will|milestone|Portion ' '-i'
check "learner text" 'PLACEHOLDER' ''

# 4. A milestone ID. Case-sensitive on purpose: "a1" in a hostname is not one.
check "learner text" '(^|[^A-Za-z0-9])(A[1-4]|B[1-3]|C[1-3]|D[1-4]|M0|INT)([^A-Za-z0-9]|$)' ''

# 5. A local path: a folder on one machine, which means nothing to a reader.
# The shapes are spelled in pieces, so this file does not carry one itself.
p_tilde='~/'
p_projects="Pro""jects"
p_home="/ho""me/"
p_docs="Docu""ments/"
p_scaffold="aws-secure-file-upload-""scaffold"
check "local path" "$p_tilde$p_projects|$p_home|$p_docs|$p_scaffold" ''

# 6. A secret-looking string. The shapes are written with a bracket class so
# this file, and a workflow that scans for the same shapes, do not match itself.
check secret 'AKIA[0-9A-Z]{16}' ''
check secret '-----BEGIN [A-Z ]*PRIVATE KEY-----' ''
check secret 'gh[pousr]_[A-Za-z0-9]{20,}' ''
check secret 'xox[baprs]-[A-Za-z0-9-]{10,}' ''
check secret 'aws_secret_access_key[[:space:]]*=' ''

# 7. A loose end. The word boundary keeps a mktemp template (XXXXXX) out of it.
check "loose end" '(^|[^A-Za-z])(TODO|FIXME)([^A-Za-z]|$)' ''

# 8. The anchors: a repository that lost its front page or its license is worse
# than one with a stale note.
for p in README.md docs/architecture.md docs/decisions.md LICENSE evidence/README.md; do
  if [ ! -f "$root/$p" ]; then report missing "$p"; fi
done

if [ "$problems" -eq 0 ]; then
  echo "SHIP: clean. No scaffolding, learner text, local paths, or secrets."
  exit 0
fi

counts=""
[ "$n_scaffold" -gt 0 ] && counts="$counts $n_scaffold scaffolding,"
[ "$n_grader" -gt 0 ] && counts="$counts $n_grader grader(s),"
[ "$n_phrase" -gt 0 ] && counts="$counts $n_phrase learner text,"
[ "$n_path" -gt 0 ] && counts="$counts $n_path local path(s),"
[ "$n_secret" -gt 0 ] && counts="$counts $n_secret secret(s),"
[ "$n_todo" -gt 0 ] && counts="$counts $n_todo loose end(s),"
[ "$n_missing" -gt 0 ] && counts="$counts $n_missing missing,"
counts=${counts%,}
echo
echo "SHIP: $problems problem(s):$counts"
echo "Remove or rewrite each one, then run this again. It must print \"SHIP: clean.\""
exit 1
