#!/usr/bin/env bash
# Why a step failed, and which part of the brief to re-read.
#
#   .github/scripts/check.sh A1 all | scripts/why.sh A1 2
#   scripts/why.sh A1 2 --explain        the same, then that step's raw output
#   scripts/why.sh --summary A1          the progress summary alone
#   scripts/why.sh --next A1             the number of the first failed step
#
# It reads the check's own output on stdin, so it works for the run on your
# machine and for the run on GitHub: scripts/check-local.sh and
# scripts/remote-check.sh both call it. Nothing here knows the answer; every
# line comes from the check's output or from the brief named on that line.
set -uo pipefail
cd "$(dirname "$0")/.."

use() {
  cat <<'EOF'
Usage: scripts/why.sh <milestone> <step> [--explain]   read .github/scripts/check.sh output on stdin
       scripts/why.sh --summary <milestone>
       scripts/why.sh --first <milestone>             the first thing to fix: a gate, then a step
       scripts/why.sh --next <milestone>
EOF
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# One line per record, without the "\tjob\tstep\t" prefix and the timestamp a
# log line carries, so the same code reads a terminal run and a GitHub run.
# Colour goes too: `tf init` and `tf validate` print it (check.sh does not pass
# -no-color to them), and an escape sequence between the indentation and the
# word would defeat every match below.
normalize() {
  tr -d '\r' | tr -d '\357\273\277' | tr -d '\033' | sed -E 's/\[[0-9;]*[mK]//g' | awk -F'\t' '
    NF >= 3 { s = ""; for (i = 3; i <= NF; i++) s = s (i > 3 ? "\t" : "") $i; print s; next }
    { print }
  ' | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z ?//'
}

tmp=$(mktemp "${TMPDIR:-/tmp}/why.XXXXXX") || exit 1
trap 'rm -f "$tmp" "$tmp.v" "$tmp.blk" "$tmp.clean"' EXIT

mode=why
case "${1:-}" in
  ""|-h|--help) use; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
  --summary) mode=summary; shift ;;
  --first) mode=first; shift ;;
  --next) mode=next; shift ;;
esac

target=$(upper "${1:-}")
if [ -z "$target" ]; then use; exit 2; fi
shift

step=""
explain=0
for arg in "$@"; do
  case "$arg" in
    --explain) explain=1 ;;
    -h|--help) use; exit 0 ;;
    *[!0-9]*) echo "❌ scripts/why.sh: \"$arg\" is not a step number."; exit 2 ;;
    *) step=$arg ;;
  esac
done

normalize > "$tmp"
grep -E '^  (✅|❌) ' "$tmp" > "$tmp.v" 2>/dev/null

# Prints the block of formatted lines that follows a verdict line, e.g. the
# detail of "  ❌ A1 step 2 (resources)".
block() { # $1 = line number of the verdict in $tmp
  awk -v start="$1" '
    NR == start { inside = 1; next }
    inside && /^  (✅|❌) / { exit }
    # The ending line of the run is not part of any block.
    inside && /^(👍 |👎 )/ { exit }
    inside { print }
  ' "$tmp"
}

# The milestone's brief, the section heading above the checkpoint, and the
# numbered items in that section since the heading. Derived from the brief, so
# a new brief needs no table here.
pointer() { # $1 = milestone, $2 = step
  brief="docs/milestones/$1.md"
  [ -f "$brief" ] || return 0
  info=$(awk -v want="$2" '
    /^> \*\*.*Checkpoint: steps? / {
      head = $0
      sub(/^.*Checkpoint:[ \t]*/, "", head)
      sub(/\(.*/, "", head)
      n = split(head, parts, /[^0-9]+/)
      hit = 0
      m = 0
      for (i = 1; i <= n; i++) {
        if (parts[i] == "") continue
        m++
        if (parts[i] == want) hit = 1
      }
      if (hit) { print NR, m; exit }
    }
  ' "$brief" 2>/dev/null)
  [ -n "$info" ] || return 0
  lineno=${info%% *}
  steps_in_block=${info##* }
  # A block that covers several steps (D2's "steps 4 and 5") has one heading in
  # front of it, so point at the item that names the step instead.
  if [ "$steps_in_block" -gt 1 ]; then
    itemline=$(head -n $((lineno - 1)) "$brief" | grep -n -E "^#### $2\." | tail -1 | cut -d: -f1)
    if [ -n "$itemline" ]; then
      found=$(head -n $((itemline - 1)) "$brief" | grep -n -E '^#{1,3} ' | tail -1)
      echo "Re-read $brief, \"${found#*:}\", item $2."
      return 0
    fi
  fi
  hline=""
  hno=""
  found=$(head -n $((lineno - 1)) "$brief" | grep -n -E '^#{1,3} ' | tail -1)
  if [ -n "$found" ]; then
    hno=${found%%:*}
    hline=${found#*:}
  fi
  if [ -z "$hline" ]; then
    echo "Re-read $brief."
    return 0
  fi
  items=$(sed -n "$((hno + 1)),$((lineno - 1))p" "$brief" \
    | grep -E '^#### [0-9]+\.' | sed -E 's/^#### ([0-9]+)\..*/\1/')
  first=$(printf '%s\n' "$items" | head -1)
  last=$(printf '%s\n' "$items" | tail -1)
  if [ -z "$first" ]; then
    echo "Re-read $brief, \"$hline\"."
  elif [ "$first" = "$last" ]; then
    echo "Re-read $brief, \"$hline\", item $first."
  else
    echo "Re-read $brief, \"$hline\", items $first to $last."
  fi
}

# Terraform draws a diagnostic's value excerpt in a box. Remove the box so only
# the words are left: a rule opens and closes the excerpt, and text inside it is
# not part of the message. The glyphs are matched byte for byte in the shell, so
# no locale or awk has to agree with the terminal about them.
unbox() { # $1 = block file, $2 = output file
  local line lead s invalue=0 buf=""
  : > "$2"
  while IFS= read -r line || [ -n "$line" ]; do
    lead=${line%%[![:space:]]*}
    s=${line#"$lead"}
    case "$s" in
      "├"*|"┌"*|"└"*)
        # A rule opens the excerpt; a second rule closes it and the buffered
        # excerpt is not part of the message.
        buf=""
        invalue=$((1 - invalue))
        continue
        ;;
      "╵"*|"╷"*)
        # The box ended without a closing rule, so what it held is text.
        if [ "$invalue" -eq 1 ] && [ -n "$buf" ]; then printf '%s' "$buf" >> "$2"; fi
        buf=""
        invalue=0
        continue
        ;;
      "│"*)
        s=${s#"│"}
        s=${s# }
        if [ "$invalue" -eq 1 ]; then buf="$buf$s"$'\n'; continue; fi
        ;;
    esac
    printf '%s\n' "$s" >> "$2"
  done < "$1"
}

# From one failed step's output, the shortest true statement of what went
# wrong: every undeclared address once, or the first message the check wrote,
# or the one file check line that failed.
collapse() { # $1 = block file
  unbox "$1" "$tmp.clean"
  addrs=$(grep -o 'A managed resource "[A-Za-z0-9_]*" "[A-Za-z0-9_]*"' "$1" 2>/dev/null \
    | sed -E 's/.*"([A-Za-z0-9_]+)" "([A-Za-z0-9_]+)".*/\1.\2/' \
    | awk '!seen[$0]++')
  if [ -n "$addrs" ]; then
    first=$(printf '%s\n' "$addrs" | head -1)
    rest=$(printf '%s\n' "$addrs" | tail -n +2 | paste -sd, - | sed 's/,/, /g')
    if [ -n "$rest" ]; then
      echo "Nothing is named $first yet. Also missing: $rest."
    else
      echo "Nothing is named $first yet."
    fi
    return 0
  fi
  lost=$(grep -E '^ *[^ ]+ is missing$' "$1" 2>/dev/null | head -1 | sed -E 's/^ +//')
  if [ -n "$lost" ]; then
    echo "$lost"
    return 0
  fi
  msg=$(awk '
    function flush() { if (cur != "") { n++; para[n] = cur; cur = "" } }
    {
      s = $0
      gsub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      if (s == "") { flush(); next }
      if (errno == 0) {
        if (s ~ /^Error: /) { errno = 1; cur = "" }
        next
      }
      # A second diagnostic is a different failure; keep the first one only.
      if (s ~ /^Error: /) exit
      if (s ~ /^on .* line [0-9]+/) next
      if (s ~ /^[0-9]+:/) next
      cur = (cur == "" ? s : cur " " s)
    }
    # The useful sentence is the last paragraph that is not a bullet list: a
    # provider failure ends with the search locations it tried, and those are
    # not the message. An assertion failure has one paragraph, the sentence.
    END {
      flush()
      for (i = n; i >= 1; i--) if (substr(para[i], 1, 1) != "-") { print para[i]; exit }
      if (n > 0) print para[n]
    }
  ' "$tmp.clean")
  [ -n "$msg" ] || msg=$(sed -n 's/^ *\(..*\)$/\1/p' "$1" | awk 'NF { print; exit }')
  [ -n "$msg" ] || return 0
  errors=$(grep -c -E '^ *Error: ' "$1" 2>/dev/null || true)
  case "$errors" in ''|0|1) echo "$msg" ;; *) echo "$msg (first of $errors errors)" ;; esac
}

step_name() { # $1 = milestone, $2 = step
  local line name
  line=$(grep -E "^  (✅|❌) $1 step $2 " "$tmp.v" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    name=${line#  ✅ }
    name=${name#  ❌ }
    name=${name#"$1 step $2 "}
    printf '%s' "$name"
  fi
}

# ---------------------------------------------------------------- summary ---
# The step table and one gate line. It never assumes a gate passed: a gate row
# that was not printed is reported as missing, and a gate row that is red is
# named. It returns 1 unless the whole milestone is green, so a caller cannot
# mistake a red run for a pass.
summary() {
  local line mark name id total=0 passed=0 next="" steps=""
  local seen_fmt=0 seen_init=0 seen_validate=0
  local bad_fmt=0 bad_init=0 bad_validate=0
  local earlier="" earlier_bad="" gates_seen=0 gates_bad=""
  local finished=0 expected=0 lid
  while IFS= read -r line; do
    case "$line" in
      "  ✅ "*) mark="✅"; name=${line#  ✅ } ;;
      "  ❌ "*) mark="❌"; name=${line#  ❌ } ;;
      *) continue ;;
    esac
    case "$name" in
      "formatting (fmt -check)") seen_fmt=1; [ "$mark" = "✅" ] || bad_fmt=1 ;;
      init) seen_init=1; [ "$mark" = "✅" ] || bad_init=1 ;;
      validate) seen_validate=1; [ "$mark" = "✅" ] || bad_validate=1 ;;
      "$1 spec")
        total=$((total + 1))
        if [ "$mark" = "✅" ]; then
          passed=$((passed + 1))
          steps="${steps}  ✅ $name
"
        elif [ -z "$next" ]; then
          next="$name"
          steps="${steps}  ❌ $name      <- next
"
        else
          steps="${steps}  ❌ $name
"
        fi ;;
      "$1 step "*|"$1: "*)
        total=$((total + 1))
        if [ "$mark" = "✅" ]; then
          passed=$((passed + 1))
          steps="${steps}  ✅ ${name#"$1 "}
"
        elif [ -z "$next" ]; then
          next="$name"
          steps="${steps}  ❌ ${name#"$1 "}      <- next
"
        else
          steps="${steps}  ❌ ${name#"$1 "}
"
        fi ;;
      *)
        id=${name%% *}; id=${id%:}
        case " $earlier " in *" $id "*) ;; *) earlier="$earlier $id" ;; esac
        [ "$mark" = "✅" ] || case " $earlier_bad " in *" $id "*) ;; *) earlier_bad="$earlier_bad $id" ;; esac ;;
    esac
  done < "$tmp.v"

  gates_seen=$((seen_fmt + seen_init + seen_validate))
  [ "$bad_fmt" -eq 1 ] && gates_bad="$gates_bad, formatting (fmt -check)"
  [ "$bad_init" -eq 1 ] && gates_bad="$gates_bad, init"
  [ "$bad_validate" -eq 1 ] && gates_bad="$gates_bad, validate"

  # The check ends every complete run with "👍 ... passed." or "👎 Failed:".
  # Without one of those the log stopped early (a cancelled run, a killed
  # check.sh, the job's timeout), and "everything I saw was green" is not a pass.
  finished=0
  if grep -qE '^(👍 .*passed\.|👎 Failed:)' "$tmp"; then finished=1; fi

  # How many steps this milestone is defined to have, from the tests that
  # define them: a truncated log otherwise reports "1 of 1".
  lid=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  expected=$(ls "tests/$lid".tftest.hcl "tests/$lid".check \
    "tests/$lid"-*.tftest.hcl "tests/$lid"-*.check 2>/dev/null | wc -l | tr -d ' ')

  if [ "$gates_seen" -eq 0 ] && [ "$total" -eq 0 ]; then
    echo "$1: the run stopped before the check printed a result"
    echo "  ⚠️  no formatting, init, or validate row was printed"
    return 1
  fi

  if [ "$total" -eq 0 ]; then
    echo "$1: no steps ran"
  elif [ "$expected" -gt 0 ] && [ "$total" -lt "$expected" ]; then
    echo "$1: $passed of $expected steps done, and the check reported only $total of them"
  else
    echo "$1: $passed of $total steps done"
  fi
  if [ -n "$gates_bad" ]; then
    echo "  ❌ ${gates_bad#, } (fix this first)"
  elif [ "$gates_seen" -eq 0 ]; then
    echo "  ⚠️  no formatting, init, or validate row was printed"
  elif [ "$gates_seen" -lt 3 ]; then
    echo "  ⚠️  only $gates_seen of the three gate rows were printed"
  else
    echo "  ✅ formatting, init, validate"
  fi
  printf '%s' "$steps"
  if [ -n "$earlier" ]; then
    if [ -z "$earlier_bad" ]; then
      echo "  ✅ earlier milestones still pass ($(echo $earlier | sed 's/ /, /g'))"
    else
      echo "  ❌ earlier milestones broken:$(echo $earlier_bad | sed 's/^/ /; s/ /, /g; s/^, / /')"
    fi
  fi
  echo
  if [ "$passed" -eq "$total" ] && [ "$total" -gt 0 ] && [ "$gates_seen" -eq 3 ] &&
     [ -z "$gates_bad" ] && [ -z "$earlier_bad" ] && [ "$finished" -eq 1 ] &&
     [ "${WHY_NO_PASS:-0}" -eq 0 ]; then
    echo "👍 $1 passed."
    return 0
  fi
  if [ "$finished" -eq 0 ]; then
    echo "  ⚠️  the run stopped before the check finished: it printed no 👍 or 👎 line"
  fi
  return 1
}

# One failed step: what it was, where to re-read, and the check's own message.
step_explain() { # $1 = milestone, $2 = step
  local sname where line start
  sname=$(step_name "$1" "$2")
  where=$(pointer "$1" "$2")
  line="Next: $1 step $2"
  [ -n "$sname" ] && line="$line $sname"
  line="$line."
  [ -n "$where" ] && line="$line $where"
  echo "$line"
  start=$(grep -n -E "^  ❌ $1 step $2 " "$tmp" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$start" ]; then
    block "$start" > "$tmp.blk"
    collapse "$tmp.blk"
    if [ "$explain" -eq 1 ]; then
      echo
      cat "$tmp.blk"
    fi
  else
    echo "The check printed no detail for this step."
  fi
  echo "Run ${WHY_EXPLAIN_CMD:-scripts/check-local.sh --explain} for the full output."
}

# The first thing to fix: a red gate row (they run before every step), then the
# first red step, then the case where the run died before the check printed
# anything. Prints nothing and returns 3 when there is nothing red.
first() { # $1 = milestone
  local gate start files n red name id

  # check-local.sh runs the dependency gate and tflint before check.sh, exactly
  # as CI does. When one of those failed, it is the first thing to fix, and its
  # message is already on screen above the summary.
  if [ -n "${WHY_LOCAL_GATE:-}" ]; then
    echo "Next: $1 stopped at the ${WHY_LOCAL_GATE}, before the check itself ran. The gate's own message:"
    printf '%s\n' "${WHY_LOCAL_MSG:-}"
    echo "Its output is above the summary. CI runs this gate too, so the milestone's steps are not the problem yet."
    return 0
  fi

  for gate in "formatting (fmt -check)" init validate; do
    start=$(grep -n -F "  ❌ $gate" "$tmp" 2>/dev/null | head -1 | cut -d: -f1)
    [ -n "$start" ] || continue
    block "$start" > "$tmp.blk"
    case "$gate" in
      "formatting (fmt -check)")
        files=$(sed -E 's/^ +//' "$tmp.blk" | grep -E '\.tf$' | head -6 | paste -sd, - | sed 's/,/, /g')
        if [ -n "$files" ]; then
          echo "Next: $1 stopped at formatting (fmt -check). Terraform's formatter wants to change these files:"
          echo "$files"
        else
          echo "Next: $1 stopped at formatting (fmt -check). The check's own message:"
          collapse "$tmp.blk"
        fi
        ;;
      init)
        echo "Next: $1 stopped at init. The check's own message:"
        collapse "$tmp.blk"
        ;;
      validate)
        echo "Next: $1 stopped at validate. The check's own message:"
        collapse "$tmp.blk"
        ;;
    esac
    if [ "$explain" -eq 1 ]; then echo; cat "$tmp.blk"; fi
    echo "Run ${WHY_EXPLAIN_CMD:-scripts/check-local.sh --explain} for the full output."
    return 0
  done

  n=$(grep -E "^  ❌ $1 step [0-9]+ " "$tmp.v" 2>/dev/null | head -1 | sed -E "s/^  ❌ $1 step ([0-9]+) .*/\1/")
  if [ -n "$n" ]; then
    step_explain "$1" "$n"
    return 0
  fi

  # A red row that is not a step of this milestone: the merged milestones the
  # check re-runs, or a row this script does not know. It still gets a Next line,
  # because a learner who broke an earlier milestone needs to know which one.
  red=$(grep -E '^  ❌ ' "$tmp.v" 2>/dev/null | head -1)
  if [ -n "$red" ]; then
    name=${red#  ❌ }
    id=${name%% *}; id=${id%:}
    echo "Next: $1: $id is red ($name). The check runs every merged milestone too, so a change here can break an earlier one."
    start=$(grep -n -F "$red" "$tmp" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$start" ]; then
      block "$start" > "$tmp.blk"
      collapse "$tmp.blk"
      if [ "$explain" -eq 1 ]; then echo; cat "$tmp.blk"; fi
    fi
    echo "Re-read docs/milestones/$id.md, and run scripts/check-local.sh $id to work on it alone."
    echo "Run ${WHY_EXPLAIN_CMD:-scripts/check-local.sh --explain} for the full output."
    return 0
  fi

  # Rows exist, none is red, and the run ended: there is nothing to fix.
  if [ -s "$tmp.v" ] && grep -qE '^(👍 .*passed\.|👎 Failed:)' "$tmp"; then
    return 3
  fi

  # No verdict rows at all, or rows but no ending: the run stopped before the
  # check reported anything, so the cause is in whatever the failing step printed.
  if [ -s "$tmp.v" ]; then
    echo "Next: $1: the run stopped before the check finished. The last lines it printed:"
  else
    echo "Next: $1: nothing was checked. The run stopped before the check printed a result."
  fi
  tail -n 80 "$tmp" > "$tmp.blk"
  if grep -q '^ *\(│ *\)\?Error: ' "$tmp.blk"; then
    n=$(collapse "$tmp.blk")
  else
    # No diagnostic in the tail: the cause is the last thing the run printed,
    # not the first non-empty line of the whole log.
    n=$(grep -v -E '^  (✅|❌) ' "$tmp.blk" | grep -v '^[[:space:]]*$' | tail -1 | sed 's/^ *//')
  fi
  [ -n "$n" ] && echo "$n"
  echo "Run ${WHY_EXPLAIN_CMD:-scripts/check-local.sh --explain} for the full output."
  return 1
}

case "$mode" in
  summary) summary "$target"; exit $? ;;
  first) first "$target"; exit $? ;;
  next)
    line=$(grep -E "^  ❌ $target step [0-9]+ " "$tmp.v" 2>/dev/null | head -1)
    [ -n "$line" ] || exit 3
    printf '%s\n' "$line" | sed -E "s/^  ❌ $target step ([0-9]+) .*/\1/"
    exit 0 ;;
esac

if [ -z "$step" ]; then use; exit 2; fi

step_explain "$target" "$step"
