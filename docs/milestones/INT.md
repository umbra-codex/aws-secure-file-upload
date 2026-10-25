# INT: The last lint rule, the runbook, and the end-to-end test

| | |
|---|---|
| **Portion** | INT: Integration (one teammate leads it; everyone runs part of the test) |
| **Branch** | `int-end-to-end` |
| **Depends on** | A1 to A4, B1 to B3, C1 to C3, and D1 to D4 all merged |
| **Files you touch** | `.tflint.hcl`, `README.md`, `milestones.txt`; any file where the lint rule finds a leftover |
| **Check** | Runs on GitHub on every push to `int-end-to-end`. The branch name decides which milestone is checked, so use this exact name. |

## Goal

Four people built five modules, one reviewed pull request at a time, and each piece was checked on its own. This milestone checks that the pieces work *together*, then closes the loose ends the build left on purpose. You do three things:

- **Turn the last lint rule back on.** Until now, `tflint` ignored variables, locals, and data sources that nothing used, because a module declares its inputs before the milestone that uses them. Everything is built now, so a leftover is a mistake.
- **Write the runbook.** A short section of the README that answers "a file was quarantined, now what?" and the other questions an operator asks when something goes wrong.
- **Run the end-to-end test in a real AWS account.** Eight tests, from a clean upload to a forced failure. This is the proof that the project does what the overview says.

One teammate leads INT: that person writes the pull request and runs all eight tests. Everyone else runs tests 1, 2, and 7 in their own account, then runs `terraform destroy`, and says so in the PR. Plan about 30 minutes of work and then a wait of at least 75 minutes for test 8, which you start first.

Read A1's [How to read the blocks](A1.md#how-to-read-the-blocks) if you haven't.

## Start your branch

Do this before you change any file. It gets the latest `main` (which includes everything) and creates your branch from it:

```bash
git checkout main
git pull
git checkout -b int-end-to-end
git push -u origin int-end-to-end
```

You'll open the draft pull request at your first checkpoint: GitHub won't create a PR until the branch has at least one commit that `main` doesn't. See A1's [Start your branch](A1.md#start-your-branch) for what each line does, and A1's [Commit messages](A1.md#commit-messages) for the format every checkpoint below follows.

## Part 1: The last lint rule (`.tflint.hcl`)

#### 1. Turn on `terraform_unused_declarations`

**Tags:** not applicable (this is a configuration file, not a Terraform block).

**Docs:** [terraform_unused_declarations](https://github.com/terraform-linters/tflint-ruleset-terraform/blob/v0.15.0/docs/rules/terraform_unused_declarations.md) · [TFLint configuration](https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md)

Open `.tflint.hcl`. It ends with a comment and a rule block that sets `enabled = false`. Replace both with this rule, written on **one line** (the check matches it as text), and rewrite the comment above it so it says why the rule is on now:

| Setting | Value |
|---|---|
| Rule name | `terraform_unused_declarations` |
| `enabled` | `true` |

The finished line has the shape `rule "<name>" { enabled = <value> }`. Then open `milestones.txt` and delete the comment line that starts `# INT:`, the reminder to do this step.

**What the rule does.** It reports a `variable`, a `locals` entry, or a `data` source that is declared and never read. Terraform itself doesn't mind an unused one, so without this rule, leftovers pile up unseen.

**How you see the result.** `tflint` is not one of the numbered steps. It is a separate step of the run on GitHub (Actions, the newest run) that comes after the check, and GitHub skips it while any numbered step is ❌. So you won't see its findings until step 3 is ✅: finish the runbook, then open the **tflint** step of that run. On a correct build it prints nothing. If it reports `variable "x" is declared but not used`, a milestone left something behind. Fix it in this PR: delete the declaration, along with any argument that only existed to feed it, or use it if it was meant to be used. Leave exactly one block for the rule (your reviewer checks that the old one is gone), and do not turn the rule off again. If the finding is in someone else's module, tell them in the PR and make the smallest fix; a reviewer from that portion approves it.

**✅ Checkpoint: step 1 (tflint)**
Save `.tflint.hcl` and `milestones.txt`, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:

```bash
scripts/check-local.sh
```

Step 1 should now be ✅. It confirms the rule is enabled on one line, written exactly as above. Step 2 (wiring) builds nothing and should already be ✅ if every earlier portion finished; if it is ❌, its message lists the module outputs that are still placeholders, so ask that portion's owner to finish. Step 3 stays ❌ until you build it.

Then format, commit, push, and open your draft pull request (the `gh pr create` line is only needed this once):

```bash
terraform fmt -recursive
git add -A && git commit -m "feat(int): turn on the unused declarations lint rule" && git push
gh pr create --fill --draft
```

The push runs the same check on GitHub.

## Part 2: The wiring gate (nothing to build)

#### 2. Step 2 checks everyone's work at once

Step 2 reads the whole stack with a mocked AWS provider and checks that none of the module outputs still holds a `placeholder` value. Every portion started with placeholder outputs, and every milestone replaced some of them. A placeholder that survives means a milestone was merged without finishing its outputs, and a module further down the line would be quietly using a fake value.

You don't write anything for this step. If it is ❌, the failure message lists the outputs by name, for example `processing.router_lambda_arn`. The owner of that module fixes it in a normal pull request, and your branch passes after it merges.

## Part 3: The runbook (`README.md`, the repo root)

#### 3. Add a Runbook section

A runbook is the page someone opens at 2 a.m. when something is wrong. It is short and answers questions in the order they come up. Add a `## Runbook` section to the root `README.md`, after the "Cost and cleanup" section, with these four subsections. Each one is a heading, so the check can find it: use the headings in the first column of the table (the check looks for the key word, in either case, so a close variant is fine). The content is yours to write from what you know of the system, and your reviewer reads it.

| Subsection heading (suggested) | It must answer |
|---|---|
| `### A file was quarantined, now what` | A **table** with one row for each of the seven `reason` values: `THREATS_FOUND`, `UNSUPPORTED`, `ACCESS_DENIED`, `FAILED`, `INVALID_TYPE`, `TOO_LARGE`, `STALE`. Each row says what the reason means and what the operator should do. Say how to look a file up (the status endpoint, the DynamoDB row) and that nobody but the router can read the Quarantine bucket, though anyone with access can list it. |
| `### An upload is stuck as PENDING` | What are the possible causes (not uploaded yet, still being scanned, the router failed), and where to look for each. Say when `PENDING` turns into `EXPIRED`, and what then happens to the row. |
| `### Events are in a failure queue` | There are two: the scan DLQ and `router-failures`. Say what each one holds, name its Terraform output (`scan_dlq_name` and `router_failures_queue_url`), and say that `scripts/redrive.sh` replays `router-failures`. |
| `### An alert email arrived` | The two kinds (a quarantined file, a scanner problem) and what to do about each. |

Write it for someone who didn't build the system. Name the Terraform outputs and the commands. Don't repeat the whole design: link to the portion documents in `docs/portions/` (for example `docs/portions/d-processing.md`) instead.

**Tags:** not applicable (this is documentation).

**Docs:** [Runbooks in the AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/ops_ready_to_support_use_runbooks.html) · [Markdown tables](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-tables)

**✅ Checkpoint: step 3 (runbook)**
Save `README.md`, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:

```bash
scripts/check-local.sh
```

Step 3 should now be ✅. It confirms a Runbook heading, the four subsections, a table row for each of the seven reasons, and mentions of `scripts/redrive.sh`, `scan_dlq_name`, and `router_failures_queue_url`. It can't judge whether the advice is right; your reviewer does. Every step should now be ✅ and the summary should say `👍 INT passed.` The summary covers the numbered steps only: tflint runs after them, so also check that the run as a whole is green on your PR. Next: "Done when" below.

Then format, commit, and push:

```bash
terraform fmt -recursive
git add -A && git commit -m "docs(int): add the runbook" && git push
```

The push runs the same check on GitHub.

## Check it

### How to see your results

The check runs in two places. `scripts/check-local.sh` runs it on your machine at every checkpoint, and A1's [How to see your results](A1.md#how-to-see-your-results) explains that screen. GitHub runs it on every push, and the results are stored there: on the run's page under **Actions**, and on your pull request as the **ci** check.

**After a push (automatic):** open the repo on GitHub, click **Actions**, click the newest run, and scroll to **Summary**. The table lists every step with ✅ or ❌. Click **Output of the failed steps** under it to see what each ❌ expected and what it found.

**On GitHub, from your terminal:**

```bash
scripts/remote-check.sh
```

This follows the run your push started, waits for it if it is still running, and prints the same summary. When the milestone is complete, it looks like this:

```
Checking the last commit you pushed to int-end-to-end (3f2c1ab)
Looking for the run your push started...
Run finished in 71s

INT: 3 of 3 steps done
  ✅ formatting, init, validate
  ✅ step 1 (tflint)
  ✅ step 2 (wiring)
  ✅ step 3 (runbook)
  ✅ earlier milestones still pass (M0, A1, A2, A3, A4, B1, B2, B3, C1, C2, C3, D1, D2, D3, D4)

👍 INT passed.

Full results: https://github.com/umbra-codex/aws-secure-file-upload/actions/runs/123456789
```

The list of earlier milestones is whatever `milestones.txt` holds on your branch, so yours may differ from this example. If any line shows ❌, the first one is marked `<- next`, and the last line names the step to fix. It checks what you have **pushed**, not unsaved edits; if you have uncommitted changes or unpushed commits, it says so first. Nothing is saved on your machine: close the terminal and the results are still on GitHub. It needs the GitHub CLI, signed in (`gh auth login`). If the script itself fails, open the newest run under **Actions** instead; the same table is in its Summary.

**To re-check after a fix:** fix the file, run `scripts/check-local.sh` until the step is ✅, then format, commit, and push. The push runs the check on GitHub, and `scripts/remote-check.sh` follows that run.

INT runs in three steps:

| Step | File | Checks |
|---|---|---|
| 1 (tflint) | .tflint.hcl | the unused-declarations rule is on, as one line |
| 2 (wiring) | (nothing to build) | no module output is still a placeholder, so every portion finished |
| 3 (runbook) | README.md | a Runbook section with the four situations, the seven reasons, and the redrive script |

Every milestone already listed in `milestones.txt` is re-checked too, so a red row can name an earlier milestone: `scripts/check-local.sh <that milestone>` works on it alone. When a gate row is ❌ or the step table never appears, the `Next:` line names the gate that failed and prints the check's own message; for `formatting` it lists the files `terraform fmt` would change. See A1's [Check it](A1.md#check-it) for how to read each kind of failure.

## Done when (in your own AWS account)

This is the real test. It needs the AWS CLI v2 (`aws --version` should start with `aws-cli/2.`), `jq`, `curl`, and `zip` (`zip --version`; install it first if it is missing). It deploys the **whole** project, so everything must be merged. Use small test files: GuardDuty bills per GB scanned.

Run all the blocks below in **one terminal window**, in order: the later commands use variables and functions the earlier ones define. **Everyone** runs blocks 1, 3, 5, and 7 (the setup, tests 1 and 2, test 7, and the cleanup). **The INT lead** runs every block and pastes the whole output into the PR. Test 8 needs at least 75 minutes, so the lead starts it right after block 1.

**Block 1: setup and helpers (everyone).** From the repo root:

```bash
terraform init -backend-config=backend.hcl
terraform apply
exec > >(tee ~/int-done.txt) 2>&1
set -x
API=$(terraform output -raw api_url); API=${API%/}
INCOMING=$(terraform output -raw incoming_bucket_name)
APPROVED=$(terraform output -raw approved_bucket_name)
QUARANTINE=$(terraform output -raw quarantine_bucket_name)
QUEUE=$(terraform output -raw router_failures_queue_url)
MAX_MB=$(echo var.max_size_mb | terraform console)
T=$(mktemp -d)

upload() { # usage: upload <filename> <file>; requests an upload URL, uploads the file, sets ID, prints the HTTP code
  local resp form
  resp=$(curl -s -X POST "$API/upload-url" -H "Content-Type: application/json" \
    -d "{\"filename\": \"$1\", \"content_type\": \"image/png\", \"size\": 1024}")
  ID=$(echo "$resp" | jq -r .upload_id)
  [ "$ID" != null ] || { echo "no upload_id in the response: $resp"; return 1; }
  form=(); while IFS= read -r f; do form+=(-F "$f"); done < <(echo "$resp" | jq -r '.fields | to_entries[] | "\(.key)=\(.value)"')
  curl -s -o /dev/null -w "%{http_code}\n" "${form[@]}" -F "file=@$2" "$(echo "$resp" | jq -r .url)"
}
final() { # usage: final <upload_id>; waits up to 5 minutes for a status other than PENDING, then prints the status response
  local s
  for i in $(seq 30); do
    s=$(curl -s "$API/status/$1")
    [ "$(echo "$s" | jq -r .status)" != PENDING ] && break
    sleep 10
  done
  echo "$s"
}
```

The upload request declares a size of 1024 bytes for every file. That field only has to be a whole number between 1 and the limit: Lambda 1 records it, and the real size limit is enforced by S3 on the upload itself (B2).

**Block 2: start test 8 (INT lead only).** Request an upload URL now and never use it:

```bash
ID8=$(curl -s -X POST "$API/upload-url" -H "Content-Type: application/json" \
  -d '{"filename": "never.png", "content_type": "image/png", "size": 1024}' | jq -r .upload_id)
echo "test 8 upload: $ID8, started $(date)"
```

**Block 3: tests 1 and 2 (everyone).**

```bash
# 1. A clean file: expect APPROVED. If this fails, stop and check the scanner before reading anything into tests 2 to 4
{ printf '\x89PNG\r\n\x1a\n'; head -c 2048 /dev/urandom; } > "$T/clean.png"
upload clean.png "$T/clean.png"; final "$ID"
aws s3 ls "s3://$APPROVED/uploads/$ID/"

# 2. The EICAR test file (harmless, every scanner flags it): expect QUARANTINED, THREATS_FOUND, and an alert email
printf '%s%s' 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-' 'ANTIVIRUS-TEST-FILE!$H+H*' > "$T/eicar.png"
upload eicar.png "$T/eicar.png"; final "$ID"
aws s3 ls "s3://$QUARANTINE/uploads/$ID/"
```

EICAR is a harmless 68-character text file that every virus scanner reports as malware, made for exactly this test. The command builds it from two pieces, so this document itself isn't flagged by antivirus software. If your own antivirus deletes the file as you create it, that's it working: pause its real-time protection for a minute, or create the file in a folder it ignores.

**Block 4: tests 3 to 6 (INT lead only).**

```bash
# 3. A password-protected zip, sent as if it were a PNG: expect QUARANTINED, UNSUPPORTED
zip -q -j -P secret "$T/locked.zip" "$T/clean.png"
upload locked.png "$T/locked.zip"; final "$ID"

# 4. A Windows executable renamed to .png: expect QUARANTINED, INVALID_TYPE
{ printf 'MZ\x90\x00\x03\x00\x00\x00'; head -c 512 /dev/zero; } > "$T/fake.png"
upload invoice.png "$T/fake.png"; final "$ID"

# 5. Too large. First, an API request that declares a size over the limit: expect 400. Then a real
#    file over the limit sent with a valid form: S3 rejects it. Expect 400 and an empty listing
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API/upload-url" -H "Content-Type: application/json" \
  -d "{\"filename\": \"big.png\", \"content_type\": \"image/png\", \"size\": $(( (MAX_MB + 1) * 1024 * 1024 ))}"
head -c $(( (MAX_MB + 1) * 1024 * 1024 )) /dev/zero > "$T/big.png"
upload big.png "$T/big.png"
aws s3 ls "s3://$INCOMING/uploads/$ID/"

# 6. Recovery. First take a permission away: in modules/processing/iam.tf, remove the Approved bucket's ARN
#    from the resources of the WriteDestinations statement. Do not commit it. Then:
terraform apply
sleep 15
upload clean.png "$T/clean.png"; ID6=$ID
for i in $(seq 30); do
  N=$(aws sqs get-queue-attributes --queue-url "$QUEUE" --attribute-names ApproximateNumberOfMessages \
    --query Attributes.ApproximateNumberOfMessages --output text)
  [ "$N" != 0 ] && break
  sleep 10
done
echo "messages in router-failures: $N"
curl -s "$API/status/$ID6"
#    Now put the permission back, apply, replay, and prove the file is restored:
git checkout modules/processing/iam.tf
terraform apply
sleep 15
scripts/redrive.sh
curl -s "$API/status/$ID6"
git diff --exit-code modules/processing/iam.tf && echo "iam.tf is back to what is committed"
```

**Block 5: test 7 (everyone).**

```bash
# 7. Nothing drifted: expect "No changes" and exit code 0
terraform plan -detailed-exitcode; echo "plan exit code: $?"
```

**Block 6: test 8 (INT lead only, at least 75 minutes after block 2).**

```bash
curl -s "$API/status/$ID8"
```

**Block 7: cleanup (everyone).** Test 8 must be checked before this: `destroy` deletes the row.

```bash
# Empty the buckets: Incoming is versioned, so remove every version and delete marker
aws s3 rm "s3://$APPROVED" --recursive
aws s3 rm "s3://$QUARANTINE" --recursive
aws s3api list-object-versions --bucket "$INCOMING" --output json \
  --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' > "$T/versions.json"
[ "$(jq '.Objects | length' "$T/versions.json")" != 0 ] && aws s3api delete-objects --bucket "$INCOMING" --delete "file://$T/versions.json"
rm -r "$T"
terraform destroy
```

Expected:

1. `204`, then `{"upload_id": "...", "status": "APPROVED"}`, and one line ending in `clean.png` in the Approved listing.
2. `204`, then `"status": "QUARANTINED"` with `"reason": "THREATS_FOUND"`, one line in the Quarantine listing, and an email from the alerts topic within a few minutes (C3).
3. `QUARANTINED` with `UNSUPPORTED`.
4. `QUARANTINED` with `INVALID_TYPE`.
5. `400` from the API request, then `400` from S3 on the upload (S3 answers `EntityTooLarge`), and an **empty listing**: the listing is what proves the file never arrived.
6. `messages in router-failures: 1`, the status `PENDING` while the permission is missing, then `Replayed 1 event(s).`, `"status": "APPROVED"`, and `iam.tf is back to what is committed`.
7. `No changes. Your infrastructure matches the configuration.` and `plan exit code: 0`. Test 7 can only see a difference between your files and what is deployed. It cannot see an edit that is both saved and applied, which is why test 6 ends by checking the file with `git diff`.
8. `"status": "EXPIRED"`. An upload that is never used reads `PENDING` until its `expires_at`, which is 75 minutes after the request (15 for the upload window and 60 more), and `EXPIRED` after. If you still see `PENDING`, the time has not passed: wait and ask again.

Things that commonly go wrong:

- **Test 1 stays `PENDING`**: follow the file. Is the scanner on? `aws guardduty get-malware-protection-plan --malware-protection-plan-id "$(terraform output -raw guardduty_plan_id)" --query Status` should say `ACTIVE`. Did the scan finish? `aws s3api get-object-tagging --bucket "$INCOMING" --key "uploads/$ID/clean.png"` shows a `GuardDutyMalwareScanStatus` tag once it has. Did the router run? `aws logs tail "/aws/lambda/$(terraform output -raw router_function_name)" --since 15m` shows its log lines. The "Done when" sections of [C2](C2.md) and of D1 to D4 (see `docs/portions/d-processing.md`) cover the rest of the chain.
- **`no upload_id in the response`**: the API did not answer as expected. The body is printed; the usual causes are a wrong `API` value or a route problem (B2).
- **Test 2 shows `APPROVED`**: the EICAR string was changed when you pasted it. It must be the two pieces exactly as written, with nothing added.
- **No alert email**: confirm the SNS subscription in your inbox (C3). The email is a separate check from the quarantine.
- **Test 3 says `APPROVED`**: the file is not password-protected. Check that `zip` accepted `-P`.
- **Test 4 is not `INVALID_TYPE`**: GuardDuty's verdict on an executable header followed by zeros is not guaranteed. The router's log shows the verdict it got. The type check itself is proven by D3's "Done when", which skips the scanner.
- **Test 5 prints `204`**: the upload form's size limit is missing (B2).
- **Test 6 prints `messages in router-failures: 0`**: the first scan may not have finished, or the permission change did not propagate. Check that `terraform plan` shows nothing left to do, and ask the status endpoint again; the loop waits 5 minutes. `DestinationDeliveryFailures` for the router in CloudWatch counts records Lambda could not write to the queue.
- **Test 7 shows changes**: read the diff, because it names exactly what drifted. If it lists the `WriteDestinations` statement, you restored `iam.tf` but did not apply.
- **`scripts/redrive.sh` prints `Replayed 0 event(s).`**: the queue was empty when it looked. Queue counts can lag by a minute, so wait and run it again.

Before you commit, run `git status --short`. It must list only `.tflint.hcl`, `README.md`, `milestones.txt`, and any lint fix from Part 1. If `modules/processing/iam.tf` is listed, test 6's edit is still in your working copy: run `git checkout modules/processing/iam.tf`, because committing it would weaken the router's permissions for everyone.

Add `INT` to `milestones.txt`, then format, commit, and push:

```bash
terraform fmt -recursive
git add -A && git commit -m "chore(int): add INT to milestones.txt" && git push
```

Before you mark it ready, check GitHub once. `scripts/remote-check.sh` follows the run your last push started and prints the same summary, and it needs no new commit or push ([A1](A1.md#how-to-see-your-results) explains the output):

```bash
scripts/remote-check.sh
```

Paste the "Done when" output into your draft PR. For the lead, that is all eight tests; for everyone else, it is tests 1, 2, and 7, with a line saying so. The tflint step of the run must be green too: the summary table covers the numbered steps only, so look at the run's overall mark on the PR. The repo is squash-only, so the PR's title becomes the commit on `main`, and `--fill` named it after your first checkpoint. Retitle it to the whole milestone, then mark it ready (see A1's [Mark the pull request ready](A1.md#mark-the-pull-request-ready)):

```bash
gh pr edit --title "feat(int): turn on the last lint rule, add the runbook, and prove the stack end to end"
gh pr ready
```

When this merges, the project is built. [SHIP](SHIP.md) is the last milestone: it removes the build scaffolding and rewrites the README for a reader. Run `terraform destroy` if you haven't, and delete your state bucket only when you are sure you are finished.


**Evidence for the pull request.** `~/int-done.txt` records every command and its output from `apply` onward, so a reviewer sees what you ran and what it answered. Wrap it as the body and send it, then stop the trace:

```bash
{ echo '## Done when'; echo '```'; sed -E '/^\+ (tofu|terraform) destroy/,$d' ~/int-done.txt; echo '```'; } > ~/int-pr.md
gh pr edit --body-file ~/int-pr.md
set +x
```

## After the merge

Merge the pull request on GitHub, then clean up the branch:

```bash
git switch main && git pull
git branch -D int-end-to-end
git fetch --prune
```

`-D` rather than `-d` because this repo is squash-only: the branch's commits are never in `main` as themselves, so `git branch -d` refuses. The remote branch is already gone — `delete_branch_on_merge` removes it at merge — so `git fetch --prune` only clears the stale `origin/int-end-to-end` ref.
