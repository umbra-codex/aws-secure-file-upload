#!/usr/bin/env bash
# The summary and the pointer, from a saved GitHub run. Offline, deterministic,
# and the same code paths the two front ends use.
#
#   bash tests/scripts/summarize.test.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tests/scripts/lib.sh

log=tests/fixtures/sample-log.txt
if [ ! -f "$log" ]; then
  echo "❌ missing $log"
  exit 1
fi

summary=$(bash scripts/why.sh --summary A1 < "$log")
has "A1: 1 of 5 steps done" "$summary" "the summary counts the steps"
has "❌ step 2 (resources)      <- next" "$summary" "the first red step is marked"
has "✅ earlier milestones still pass (M0)" "$summary" "earlier milestones are reported"

n=$(bash scripts/why.sh --next A1 < "$log")
if [ "$n" = "2" ]; then ok "--next names the first red step"; else no "--next names the first red step" "got: $n"; fi

why=$(bash scripts/why.sh A1 2 < "$log")
has "A1 step 2 (resources)" "$why" "why names the step"
has '### main.tf' "$why" "why names the brief section"
has "items 5 to 9" "$why" "why names the item numbers"
for address in \
  aws_s3_bucket.this \
  aws_s3_bucket_public_access_block.this \
  aws_s3_bucket_versioning.this \
  aws_s3_bucket_cors_configuration.this; do
  has "$address" "$why" "why lists $address"
done
has "Run scripts/check-local.sh --explain" "$why" "why points at --explain"

lines=$(printf '%s\n' "$why" | grep -c .)
if [ "$lines" -le 6 ]; then ok "why fits on $lines lines"; else no "why fits on six lines" "got $lines"; fi

raw=$(bash scripts/why.sh A1 2 --explain < "$log")
has "tests/a1-2-resources.tftest.hcl" "$raw" "--explain adds the raw output"

# A section whose items are a table, not headings, prints the heading only.
table=$(bash scripts/why.sh A1 3 < "$log")
has '### outputs.tf' "$table" "a table section prints the heading"
hasnt "items " "$table" "a table section prints no item numbers"

# A block that covers two steps points each one at its own item.
multi4=$(printf '  ❌ D2 step 4 (config)\n     m\n' | bash scripts/why.sh D2 4)
multi5=$(printf '  ❌ D2 step 5 (order)\n     m\n' | bash scripts/why.sh D2 5)
has '## Part 3' "$multi4" "step 4 of a two-step checkpoint gets its own section"
has 'item 4' "$multi4" "step 4 of a two-step checkpoint gets its own item"
has '## Part 4' "$multi5" "step 5 of a two-step checkpoint gets its own section"
has 'item 5' "$multi5" "step 5 of a two-step checkpoint gets its own item"

# The seam the older script already had.
seam=$(bash scripts/remote-check.sh --summarize A1 < "$log")
has "A1: 1 of 5 steps done" "$seam" "remote-check.sh --summarize still works"

# A gate that fails before any step runs: the summary names it, never calls it
# green, and the first-thing-to-fix line carries the check's own message.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/summarize.XXXXXX") || exit 1
printf '%s\n' \
  '  ❌ init' \
  '     ╷' \
  '     │ Error: Failed to install provider' \
  '     │ Error while installing hashicorp/aws v6.69.1: could not query provider registry' \
  '     ╵' > "$tmp/gate.log"
gate_sum=$(bash scripts/why.sh --summary A1 < "$tmp/gate.log")
gate_rc=$?
has "❌ init (fix this first)" "$gate_sum" "a red gate row is named in the summary"
has "A1: no steps ran" "$gate_sum" "a gate-only failure does not claim a step count"
hasnt "0 of 0 steps done" "$gate_sum" "a gate-only failure is not reported as a count"
hasnt "✅ formatting, init, validate" "$gate_sum" "a red gate is never reported as green"
if [ "$gate_rc" -eq 1 ]; then ok "a gate-only failure exits non-zero"; else no "a gate-only failure exits non-zero" "got $gate_rc"; fi
gate_why=$(bash scripts/why.sh --first A1 < "$tmp/gate.log")
has "stopped at init" "$gate_why" "the first thing to fix is the gate"
has "could not query provider registry" "$gate_why" "the gate's own message is printed"

# A run that stopped before the check printed anything: not a clean gate row.
printf '%s\n' 'docs/milestones/A1.md:312: the checkpoint block does not name scripts/check-local.sh' > "$tmp/dead.log"
dead_sum=$(bash scripts/why.sh --summary A1 < "$tmp/dead.log")
dead_rc=$?
has "the run stopped before the check printed a result" "$dead_sum" "a run with no rows says so"
hasnt "0 of 0 steps done" "$dead_sum" "a run with no rows is not reported as a count"
hasnt "✅ formatting, init, validate" "$dead_sum" "a run with no rows is never called green"
if [ "$dead_rc" -eq 1 ]; then ok "a run with no rows exits non-zero"; else no "a run with no rows exits non-zero" "got $dead_rc"; fi
dead_why=$(bash scripts/why.sh --first A1 < "$tmp/dead.log")
has "nothing was checked" "$dead_why" "the first thing to fix says nothing was checked"
has "does not name scripts/check-local.sh" "$dead_why" "the cause of the stop is printed"

# Formatting red while every step is green.
printf '%s\n' \
  '  ❌ formatting (fmt -check)' \
  '     main.tf' \
  '  ✅ init' \
  '  ✅ validate' \
  '  ✅ A1 step 1 (variables)' > "$tmp/fmt.log"
fmt_sum=$(bash scripts/why.sh --summary A1 < "$tmp/fmt.log")
has "❌ formatting (fmt -check) (fix this first)" "$fmt_sum" "the failing formatter gate is named"
fmt_why=$(bash scripts/why.sh --first A1 < "$tmp/fmt.log")
has "wants to change these files" "$fmt_why" "the formatting failure says what fmt wants"
has "main.tf" "$fmt_why" "the formatting failure names the file"

# The box Terraform draws around a value excerpt is not part of the message.
printf '%s\n' \
  '  ❌ A1 step 2 (resources)' \
  '     Error: Test assertion failed' \
  '     ' \
  '       on tests/a1-2-resources.tftest.hcl line 44, in run "bucket_basics":' \
  '       44:     condition     = aws_s3_bucket.this.tags' \
  '     ' \
  '     ├────────────────────────────────────────' \
  '     │ aws_s3_bucket.this.tags is map of string with 1 element' \
  '     ├────────────────────────────────────────' \
  '     The bucket has the wrong Role tag: expected "incoming".' \
  '     ╵' > "$tmp/assert.log"
asserted=$(bash scripts/why.sh A1 2 < "$tmp/assert.log")
has 'The bucket has the wrong Role tag: expected "incoming".' "$asserted" "the assertion's own sentence survives"
hasnt '├' "$asserted" "the value excerpt's box is not pasted into the hint"
hasnt 'map of string' "$asserted" "the value excerpt itself is dropped"

# The same shape with the message drawn inside the box still yields the message.
printf '%s\n' \
  '  ❌ A1 step 2 (resources)' \
  '     Error: Test assertion failed' \
  '       on tests/a1-2-resources.tftest.hcl line 44, in run "bucket_basics":' \
  '       44:     condition     = aws_s3_bucket.this.tags' \
  '     ├────────────────────────────────────────' \
  '     │ aws_s3_bucket.this.tags is map of string with 1 element' \
  '     │ The bucket has the wrong Role tag: expected "incoming".' \
  '     ╵' > "$tmp/assert2.log"
asserted2=$(bash scripts/why.sh A1 2 < "$tmp/assert2.log")
has 'The bucket has the wrong Role tag: expected "incoming".' "$asserted2" "a boxed message still survives"
# A run that stops mid-way: gates green, one step green, no ending line. It is
# not a pass, and the count comes from the milestone's own tests, not the log.
printf '%s\n' \
  '  ✅ formatting (fmt -check)' \
  '  ✅ init' \
  '  ✅ validate' \
  '  ✅ A1 step 1 (variables)' \
  '.github/scripts/check.sh: line 158: jq: command not found' > "$tmp/crash.log"
crash_sum=$(bash scripts/why.sh --summary A1 < "$tmp/crash.log")
crash_rc=$?
has "A1: 1 of 5 steps done, and the check reported only 1 of them" "$crash_sum" "a truncated run counts against the milestone's own steps"
hasnt "👍 A1 passed." "$crash_sum" "a truncated run is never a pass"
has "the run stopped before the check finished" "$crash_sum" "a truncated run says what happened"
if [ "$crash_rc" -eq 1 ]; then ok "a truncated run exits non-zero"; else no "a truncated run exits non-zero" "got $crash_rc"; fi
crash_why=$(bash scripts/why.sh --first A1 < "$tmp/crash.log")
has "the run stopped before the check finished" "$crash_why" "the first thing to fix says the run stopped"
has "jq: command not found" "$crash_why" "the last thing the run printed is shown"

# The same shape, complete: the pass line needs the check's own ending.
printf '%s\n' \
  '  ✅ formatting (fmt -check)' \
  '  ✅ init' \
  '  ✅ validate' \
  '  ✅ A1 step 1 (variables)' \
  '  ✅ A1 step 2 (resources)' \
  '  ✅ A1 step 3 (outputs)' \
  '  ✅ A1 step 4 (readme)' \
  '  ✅ A1 step 5 (storage)' \
  '  ✅ M0 spec' \
  '👍 A1 passed.' > "$tmp/green.log"
green_sum=$(bash scripts/why.sh --summary A1 < "$tmp/green.log")
green_rc=$?
has "👍 A1 passed." "$green_sum" "a complete green run still passes"
has "✅ earlier milestones still pass (M0)" "$green_sum" "earlier milestones are reported"
if [ "$green_rc" -eq 0 ]; then ok "a complete green run exits zero"; else no "a complete green run exits zero" "got $green_rc"; fi

# A red earlier milestone: the summary names it and the Next line explains it.
printf '%s\n' \
  '  ✅ formatting (fmt -check)' \
  '  ✅ init' \
  '  ✅ validate' \
  '  ✅ A1 step 1 (variables)' \
  '  ✅ A1 step 2 (resources)' \
  '  ✅ A1 step 3 (outputs)' \
  '  ✅ A1 step 4 (readme)' \
  '  ✅ A1 step 5 (storage)' \
  '  ❌ M0 spec' \
  '     Error: Test assertion failed' \
  '       The bucket must not have public access' \
  '👎 Failed: M0 spec' > "$tmp/earlier.log"
earlier_sum=$(bash scripts/why.sh --summary A1 < "$tmp/earlier.log")
has "❌ earlier milestones broken: M0" "$earlier_sum" "a broken earlier milestone is named"
earlier_why=$(bash scripts/why.sh --first A1 < "$tmp/earlier.log")
has "M0 is red" "$earlier_why" "the first thing to fix is the earlier milestone"
has "The bucket must not have public access" "$earlier_why" "the earlier milestone's own message is printed"
has "docs/milestones/M0.md" "$earlier_why" "it points at that milestone's brief"

# M0's spec row keeps its name instead of being cut down to "spec".
printf '%s\n' \
  '  ✅ formatting (fmt -check)' \
  '  ✅ init' \
  '  ✅ validate' \
  '  ✅ M0 spec' \
  '👍 M0 passed.' > "$tmp/m0.log"
m0_sum=$(bash scripts/why.sh --summary M0 < "$tmp/m0.log")
has "M0: 1 of 1 steps done" "$m0_sum" "M0 counts its one check"
has "✅ M0 spec" "$m0_sum" "the spec row keeps its milestone's name"
has "👍 M0 passed." "$m0_sum" "M0 can pass"

# A colourised init failure: the escapes must not defeat the box or the message,
# and the search-location bullets are not the message.
esc=$(printf '\033')
printf '%s\n' \
  '  ❌ init' \
  '     ╷' \
  "     ${esc}[31m│${esc}[0m ${esc}[1m${esc}[31mError: Failed to query available provider packages${esc}[0m" \
  "     ${esc}[31m│${esc}[0m " \
  "     ${esc}[31m│${esc}[0m ${esc}[1mCould not retrieve the list of available versions for provider hashicorp/aws${esc}[0m" \
  "     ${esc}[31m│${esc}[0m " \
  "     ${esc}[31m│${esc}[0m ${esc}[1m- /home/me/empty-mirror${esc}[0m" \
  "     ${esc}[31m│${esc}[0m " \
  '     ╵' > "$tmp/colour.log"
colour_why=$(bash scripts/why.sh --first A1 < "$tmp/colour.log")
has "Could not retrieve the list of available versions" "$colour_why" "colour does not hide the error's sentence"
hasnt "[31m" "$colour_why" "no escape sequence reaches the screen"
hasnt "empty-mirror" "$colour_why" "the search locations are not the message"

rm -rf "$tmp"

report summarize
