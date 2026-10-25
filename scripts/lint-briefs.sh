#!/usr/bin/env bash
# Every checkpoint in a milestone brief must name the command the learner runs.
#
#   scripts/lint-briefs.sh
#
# Markdown has no include, so this is how 16 briefs, and the 17th someone writes
# next month, keep the rule. The heading match is case-insensitive, and a line
# that is meant to be a checkpoint heading but is not written in the one form
# this lint reads is a problem rather than a silent skip: a brief cannot drift
# out of the check by spelling. Exit 0 when every block is fine, 1 with one line
# per problem otherwise. CI runs this on every push.
set -uo pipefail
cd "$(dirname "$0")/.."

bad=0
blocks=0

# The briefs carry plain checkpoint headings; the rules below are written
# against the quoted form they used to have. Normalise a copy into a temp dir so
# one set of rules reads both shapes, and so a plain heading cannot become a
# silent skip that passes CI while checking nothing.
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
mkdir -p "$tmp/docs/milestones"
for src in docs/milestones/*.md; do
  [ -f "$src" ] || continue
  awk '
    /^## / { inb = 0 }
    /^\*\*.*[Cc]heckpoint: steps? / { inb = 1 }
    { if (inb) { if ($0 == "") print ">"; else print "> " $0 } else print }
  ' "$src" > "$tmp/docs/milestones/$(basename "$src")"
done

# The block that just ended, judged. Uses the loop's own variables.
close_block() {
  if [ "$seen" -eq 0 ]; then
    if [ "$mention" -eq 1 ]; then
      echo "$brief:$start: mentions scripts/check-local.sh but never tells the learner to run it"
    else
      echo "$brief:$start: the checkpoint block does not name scripts/check-local.sh"
    fi
    bad=$((bad + 1))
  fi
}

for bf in "$tmp"/docs/milestones/*.md; do
  [ -f "$bf" ] || continue
  brief="docs/milestones/$(basename "$bf")"
  inblock=0
  start=0
  seen=0
  mention=0
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')
    head=0
    case "$lower" in
      "> **"*"checkpoint: step "*|"> **"*"checkpoint: steps "*) head=1 ;;
    esac
    if [ "$head" -eq 1 ]; then
      if [ "$inblock" -eq 1 ]; then close_block; fi
      inblock=1
      start=$n
      seen=0
      mention=0
      blocks=$((blocks + 1))
      continue
    fi
    # Meant to be a checkpoint heading, but not in the form read above. The bare
    # "> **✅ Checkpoint**" form (M0 has those, and they carry no step) is fine.
    case "$lower" in
      ">"*"**"*"checkpoint"*)
        case "$lower" in
          *"checkpoint**"*) ;;
          *)
            echo "$brief:$n: this checkpoint heading is not written as '> **... Checkpoint: step N (...)**'"
            bad=$((bad + 1))
            if [ "$inblock" -eq 1 ]; then close_block; inblock=0; fi
            continue
            ;;
        esac
        ;;
      "#"*"checkpoint"*"step"*)
        echo "$brief:$n: a checkpoint heading outside a blockquote is not checked; write it as '> **... Checkpoint: step N ...**'"
        bad=$((bad + 1))
        continue
        ;;
    esac
    case "$line" in
      ">"*)
        if [ "$inblock" -eq 1 ]; then
          case "$line" in
            "> scripts/check-local.sh"|"> scripts/check-local.sh "*) seen=1 ;;
          esac
          case "$line" in
            *"scripts/check-local.sh"*)
              case "$line" in
                "> scripts/check-local.sh"|"> scripts/check-local.sh "*) ;;
                *) mention=1 ;;
              esac
              ;;
          esac
          case "$line" in
            *"Open the check's results"*)
              echo "$brief:$n: sends the learner to the results page instead of a command"
              bad=$((bad + 1))
              ;;
          esac
        fi
        ;;
      *)
        if [ "$inblock" -eq 1 ]; then
          close_block
          inblock=0
        fi
        ;;
    esac
  done < "$bf"
  if [ "$inblock" -eq 1 ]; then close_block; fi
done

if [ "$bad" -eq 0 ]; then
  echo "👍 $blocks checkpoint blocks in docs/milestones/ tell the learner to run scripts/check-local.sh."
  exit 0
fi
echo "👎 $bad problem(s) in $blocks checkpoint blocks."
exit 1
