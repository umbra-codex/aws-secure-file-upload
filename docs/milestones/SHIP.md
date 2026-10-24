# SHIP: Ship the repository

| | |
|---|---|---|
| **Portion** | SHIP: Ship (the lead, like INT) |
| **Branch** | `ship` |
| **Depends on** | INT (the runbook and the end-to-end test) merged |
| **Files you touch** | New: `docs/architecture.md`, `docs/decisions.md`, `evidence/README.md`, `LICENSE`. Rewritten: `README.md`, `.github/workflows/ci.yml`. Deleted: every path in the table in Part 5. |
| **Check** | Runs on GitHub on every push to `ship`. The branch name decides which milestone is checked, so use this exact name. The last step is checked by `scripts/ship-check.sh`, which is in this repository. |

## Goal

The build is finished. What is left is the repository a stranger opens. Right now it has two jobs and does neither: its front page tells a teammate which branch to push, and the design is buried in a walkthrough of the work. A recruiter or a hiring engineer gives it five minutes and leaves with nothing to go on.

This milestone turns the repository into the thing you show. By the end:

- **A stranger gets it from the first screen.** What it is, how it works, what proves it works, and what was traded away, all before scrolling twice.
- **The design stands on its own.** `docs/architecture.md` holds the flow, the decisions, and the contracts, without the schedule and the portion breakdown.
- **The proof is in the repository.** `evidence/` holds what the end-to-end test printed, `docs/decisions.md` holds why each choice was made, and `LICENSE` says what anyone may do with it.
- **A normal workflow replaces the milestone runner.** Formatting, validation, lint, a secret scan, and the product's tests on every push and every pull request. No branch name is read as a milestone any more.
- **Nothing addressed to a builder survives.** The briefs, the check runner, the helper scripts, the graders, and the words "Checkpoint" and "Done when" are gone, and `scripts/ship-check.sh` proves it.

Two rules decide every deletion. The code, the infrastructure, and the tests of the product stay. Anything that exists only to build or grade the build goes. The briefs are not lost: they live outside this repository.

Read A1's [How to read the blocks](A1.md#how-to-read-the-blocks) if you haven't.

## Start your branch

Do this before you change any file. It gets the latest `main` (which includes INT) and creates your branch from it:

```bash
git checkout main
git pull
git checkout -b ship
git push -u origin ship
```

You'll open the draft pull request at your first checkpoint: GitHub won't create a PR until the branch has at least one commit that `main` doesn't. See A1's [Start your branch](A1.md#start-your-branch) for what each line does, and A1's [Commit messages](A1.md#commit-messages) for the format every checkpoint below follows.

## Part 1: The architecture note (`docs/architecture.md`)

#### 1. Move the design out of the build overview

`docs/overview.md` is two documents in one: the design, which a stranger wants, and the plan, which only the team needed. Split it. The design goes into a new file, `docs/architecture.md`; the plan leaves in Part 5.

| Section of `docs/overview.md` | Goes to | What the new file says |
|---|---|---|
| "Where it started" | `docs/architecture.md`, as one sentence in the opening paragraph | The flow came from a first design with the right core, and a review filled the gaps. |
| "What changed, and why" (the whole table) | `docs/architecture.md`, unchanged | Each change, why it was made, and the Well-Architected pillar it serves. This is the trade-off record. |
| "Encryption and scanning" and "No VPC" | `docs/architecture.md`, unchanged | Why SSE-S3 and not SSE-C or KMS; why there is no VPC. |
| "Well-Architected, in one screen" | `docs/architecture.md`, unchanged | The pillar table. |
| "How it works now" (the Mermaid diagram and the eight numbered steps) | `docs/architecture.md`, unchanged | The flow, in one picture and eight steps. |
| "Shared contracts" (file key, DynamoDB item, module interface, permissions) | `docs/architecture.md`, unchanged | What each module promises the others. |
| "Sources" | `docs/architecture.md`, unchanged | The AWS and HashiCorp pages the design rests on. |
| "How the work is split", "Schedule", "How each milestone works", "The GitHub Actions check", "Deploying into your own account", "Final integration test (INT)" | nowhere in the repository | These are build instructions. The README says how to run the stack; the rest is kept outside the repository. |

Then add two things the overview never needed:

1. **An opening paragraph a stranger can read alone.** What the system does, the four services that do it, and one sentence on why it is built this way. Name the file key and the two buckets, since everything else refers to them.
2. **A "Decisions and trade-offs" section that links the decision log with a relative link to `decisions.md`.** Part 3 writes that file. The architecture note says what was decided; the decision log says when, why, and what it cost.

Keep the headings, because the check reads them: a title, "What it is", "Decisions and trade-offs", "Well-Architected", "Shared contracts", and "Sources". Keep the Mermaid diagram exactly as it is; it renders on GitHub and it is the one picture most readers will look at.

Do not carry over any sentence addressed to a builder: no schedule, no branch names, no "Done when", no portion letters as owners. The letters still appear inside the diagram as module owners (B signs the presigned POST, D routes the file); that is design, not a plan, and it stays.

**Tags:** not applicable (this is documentation).

**Docs:** [Diátaxis: architecture documentation](https://diataxis.fr/explanation/) · [Mermaid flowchart syntax](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams) · [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html)

> **✅ Checkpoint: step 1 (architecture)**
> Save `docs/architecture.md`, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:
> ```bash
> scripts/check-local.sh
> ```
> Step 1 should now be ✅. It confirms the title, the five section headings, the Mermaid flowchart, a table row for the DynamoDB status, the file-key contract as written, and the relative link to the decision log. It cannot tell whether the prose is any good; your reviewer reads it. Steps 2 to 4 stay ❌ until you build them. Note that `docs/overview.md` still exists, which the check in Part 5 (`scripts/ship-check.sh`) will list under `scaffolding` until you delete it; that is expected at this point.
> Then format, commit, push, and open your draft pull request (the `gh pr create` line is only needed this once):
> ```bash
> terraform fmt -recursive
> git add -A && git commit -m "docs(ship): add the architecture note" && git push
> gh pr create --fill --draft
> ```
> The push runs the same check on GitHub.

## Part 2: The README (`README.md`)

#### 2. Write the front page for the person who is not you

The README is not a manual for the team any more. It is the five minutes a stranger gives the repository. Seven sections, in this order, and each one has a job:

| Section | The question it answers | What it must contain |
|---|---|---|
| Title, one paragraph, and the badge | What is this? | The system in one sentence; the four services by name; the **ci** badge for `.github/workflows/ci.yml`, so the first thing a reader sees is that it is tested. |
| Architecture | How does it work? | A short Mermaid diagram of the flow plus the numbered steps in plain words, and a link to `docs/architecture.md` for the contracts and the trade-offs. |
| Proof it works | What proves it? | The badge, a link to the newest green run under Actions, and what `evidence/` holds: the eight end-to-end tests and their results against a real account. |
| Decisions and trade-offs | What was given up? | Four or five of the choices a reviewer would question, one line each (SSE-S3 and not KMS; Quarantine on every non-clean verdict; copy by `versionId`; no VPC; TTL instead of a cleanup job), and a link to `docs/decisions.md`. |
| Cost and teardown | What does it cost me to try? | Pay-per-use, GuardDuty billed per GB scanned, test with small files, a budget alert before the first apply, and `terraform destroy` when done. |
| How to run it | How do I run it? | Prerequisites, the state bucket, the two `.example` files, `terraform init -backend-config=backend.hcl`, `terraform plan`, `terraform apply`, and the two requests the API takes. |
| What you can verify yourself | Why should I believe any of it? | Four checks a reader can do without trusting you: read the modules; run the tests with no AWS account; read `evidence/`; compare each decision in `docs/decisions.md` against the code. |

**The five-minute test.** Read only the first screen, the title and the paragraph under it, and answer four questions: what is it, how does it work, what proves it works, and what was traded away. If any answer needs a scroll or a link, move that content up. Ask someone who has not seen the project to do it once; their questions are the edits.

What leaves the README, in the same move: the team table, the branch and milestone instructions, the CI section written for teammates, "Getting started" with the collaborator invitation, the repo layout annotated per portion, the runbook's build context, and every mention of a brief, a milestone, or `milestones.txt`. The runbook itself stays: an operator who gets a quarantined file is a real reader. Fold its four subsections into a "Problems and what they mean" section under "What you can verify yourself", or keep them as they are; just make sure the words around them are for an operator, not a teammate.

Keep the two notes that answer a reader's first objections: why bucket names include the account ID, and why there is no VPC. They are one paragraph each.

**Tags:** not applicable (this is documentation).

**Docs:** [About READMEs](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) · [Adding a workflow status badge](https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/adding-a-workflow-status-badge) · [Making a good README](https://docs.github.com/en/repositories/creating-and-managing-repositories/best-practices-for-repositories)

> **✅ Checkpoint: step 2 (readme)**
> Save `README.md`, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:
> ```bash
> scripts/check-local.sh
> ```
> Step 2 should now be ✅. It confirms the badge URL, the seven section headings, a link to `docs/architecture.md`, a link to `evidence/`, at least one fenced `bash` block, and the product-test command `terraform test`. It cannot judge the writing, and it cannot see whether the five-minute test passes; your reviewer does both.
> Then format, commit, and push:
> ```bash
> terraform fmt -recursive
> git add -A && git commit -m "docs(ship): rewrite the README for a stranger" && git push
> ```
> The push runs the same check on GitHub.

## Part 3: The proof and the paperwork (`evidence/`, `docs/decisions.md`, `LICENSE`)

#### 3. Three small files that make the claims checkable

**`evidence/README.md`.** The end-to-end run from INT is the proof that the stack does what the README says. Paste what it printed: a table with one row per test (clean file, EICAR file, locked zip, renamed executable, oversize upload, forced router failure and redrive, `plan` with no changes, expired request), the result each one produced, and the date and the run link. Say which AWS account it ran in only as "a test account". Do not paste an account ID, an ARN with an account number, or a bucket name that contains one.

**`docs/decisions.md`.** The decision log. A table with one row per decision, and four columns: the date, the decision, why it was made, and where a reader can see it in the code. Start from these six, which the build actually made:

| Date | Decision | Why | Where it shows |
|---|---|---|---|
| 2026-10-19 | SSE-S3 on every bucket, never SSE-C | GuardDuty cannot scan SSE-C objects, so every file would be quarantined | The bucket module |
| 2026-10-21 | Quarantine on every verdict except clean | Unsupported, access-denied, and failed scans are not clean either | The router's routing step |
| 2026-10-21 | Copy the exact `versionId` that was scanned, then delete it | A file replaced after the scan must not reach Approved unscanned | The router's copy and delete |
| 2026-10-21 | No VPC | Every dependency is a managed endpoint over IAM-authenticated HTTPS | The whole configuration |
| 2026-10-21 | TTL on `expires_at`, removed when a status is final | Abandoned rows clean themselves up; finished uploads stay queryable | The table and the router's update |
| 2026-10-22 | `arm64` Lambdas, on-demand table, 14-day logs | Cheapest configuration that still meets the reliability target | The function and table definitions |

Each row is one sentence in the "why" column. If a decision changed later, add a second row with the new date; do not rewrite the first one. History is the point.

**`LICENSE`.** MIT, with the year and the team as the copyright holder. GitHub reads the file and shows the license on the repository page, which is one of the things a stranger looks for.

**Tags:** not applicable (these are documentation and a license file).

**Docs:** [Adding a license to a repository](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/adding-a-license-to-a-repository) · [Choose a license](https://choosealicense.com/) · [Architecture decision records](https://adr.github.io/)

> **✅ Checkpoint: step 3 (proof)**
> Save the three files, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:
> ```bash
> scripts/check-local.sh
> ```
> Step 3 should now be ✅. It confirms `LICENSE` starts with the MIT line, `docs/decisions.md` has a title, a table, and a date, and `evidence/README.md` has a title, a table, a link to a run, and the scan verdict the malware test produced. Step 4 stays ❌ until you build it.
> Then format, commit, and push:
> ```bash
> terraform fmt -recursive
> git add -A && git commit -m "docs(ship): add the evidence, the decision log, and the license" && git push
> ```
> The push runs the same check on GitHub.

## Part 4: The normal workflow (`.github/workflows/ci.yml`)

#### 4. Replace the milestone runner with a workflow that outlives the build

The current workflow exists to grade milestones. It reads a milestone from the branch name, fetches `main`, runs the dependency gate and `scripts/lint-briefs.sh`, and filters the test files by ID. None of that means anything after this milestone, and all of it needs files that are about to be deleted. Replace the whole file with a workflow that would suit any repository.

| Part | Setting | Why |
|---|---|---|
| `name` | `ci` | The branch protection rule and the badge both point at it. Keep the name. |
| `on` | `push` and `pull_request` | Every branch and every pull request, not one milestone. |
| `permissions` | `contents: read` | The job only reads the repository. |
| `concurrency` | group `ci-${{ github.ref }}`, `cancel-in-progress: true` | A newer push cancels the older run. |
| Job | `check`, `runs-on: ubuntu-latest`, `timeout-minutes: 20` | The branch protection rule requires a check named `check`. |
| Steps, in order | checkout; set up Terraform `1.16.6` with `terraform_wrapper: false`; `terraform fmt -check -recursive`; `terraform init -backend=false -input=false`; `terraform validate -no-color`; set up `tflint` `v0.64.0`; `tflint --init` and `tflint --recursive --config "$(pwd)/.tflint.hcl"`; a secret scan; `terraform test -no-color` | The same checks the build ran, minus the milestone parts, plus a scan. |
| Secret scan | One `run` step that greps the tracked files and fails on a match for five shapes: an AWS access key ID (`AKIA` then 16 capitals or digits), a private-key header, a GitHub token (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` and then 20 or more characters, which is looser than the 36 a current token carries, so it catches a truncated paste too), a Slack token, and an `aws_secret_access_key` assignment. On a match, print the file and the line number, never the value. | GitHub's secret scanning (M0 turned it on) blocks a push that carries a known credential. This catches the shape first, in the pull request, where it is cheap to fix. |
| Product tests | `terraform test -no-color` | Every `*.tftest.hcl` in `tests/`, with the mocked AWS provider. No account, no cost. |

Two things to delete from the file while you are in it: the `workflow_dispatch` input that names a milestone, and the sed that reads a milestone out of the branch name. One thing to keep: the `check` job name, and the `timeout-minutes`, because a provider download that hangs must not hold the required check.

From this commit on, a push runs this workflow. `scripts/remote-check.sh` follows the old one, so it no longer applies: use `git push` and then `gh run watch` (`gh run watch --exit-status`), or open the repository's Actions tab.

**Tags:** not applicable (this is a workflow file).

**Docs:** [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions) · [Events that trigger workflows](https://docs.github.com/en/actions/reference/events-that-trigger-workflows) · [setup-terraform](https://github.com/hashicorp/setup-terraform) · [setup-tflint](https://github.com/terraform-linters/setup-tflint)

> **✅ Checkpoint: step 4 (workflow)**
> Save `.github/workflows/ci.yml`, then run the check in your terminal before you commit. No AWS needed; [A1](A1.md#how-to-see-your-results) explains the output:
> ```bash
> scripts/check-local.sh
> ```
> Step 4 should now be ✅. It confirms the workflow runs on `push` and on `pull_request`, and that every command the table above lists is in the file together with the step that makes it work: the checkout, the Terraform and tflint setup, `terraform init`, the formatting check, `terraform validate`, `tflint --init` and `tflint --recursive`, the secret scan, and `terraform test`. Every numbered step should now be ✅ and the summary should say `👍 SHIP passed.` This is the last commit where the milestone runner still runs; the next part deletes it.
> Then format, commit, and push:
> ```bash
> terraform fmt -recursive
> git add -A && git commit -m "ci(ship): run formatting, validation, lint, the secret scan, and the tests on every push" && git push
> ```
> The push runs the new workflow, not the milestone check. Follow it with `gh run watch --exit-status` or under **Actions**.

## Part 5: The removal

#### 5. Delete the build scaffolding, then prove it is gone

This is the part the milestone exists for. Every file below was listed from this repository, not from memory.

**What leaves.** The counts are the files in the repository the day this milestone opened.

| Path | Files | What it is | Why it goes |
|---|---|---|---|
| `docs/milestones/` | 17 briefs | The build plan, one file per milestone | The plan is kept outside the repository. A visitor needs the design, not the steps that produced it. |
| `docs/overview.md` | 1 | Build overview: schedule, portions, milestone mechanics | Its design sections are now `docs/architecture.md`; the rest is build instruction. |
| `docs/portions/` | 4 | One document per teammate's share | There is no share to divide any more. |
| `milestones.txt` | 1 | The ledger of merged milestone IDs | Only the check runner reads it. |
| `.github/owners.txt` | 1 | Maps a milestone to a GitHub handle | Nobody to notify. |
| `.github/CODEOWNERS` | 1 | Forces the lead's review of the harness | The paths it protects are going. The `main` protection rule still keeps every change behind a pull request and a green check, which is what a visitor needs. |
| `.github/pull_request_template.md` | 1 | A builder's checklist, including "My milestone ID" | It describes a process that no longer exists. |
| `.github/workflows/next.yml` | 1 | Opens an issue when a milestone becomes ready | It reads `milestones.txt` and the briefs; both leave. |
| `.github/scripts/notify.sh`, `ready.sh`, `deps.sh` | 3 | The notifier and the dependency gate | They exist to drive a build in a fixed order. |
| `.github/scripts/check.sh` | 1 | The milestone check runner | The normal workflow replaces it. |
| `scripts/` | 5 | `check-local.sh`, `why.sh`, `remote-check.sh`, `lint-briefs.sh`, `ship-check.sh` | Every one of them is a command for a learner, including the check this milestone added. |
| `tests/*.check` | 29 | Text checks: "this file must contain this line" | Each one grades a step of the build. |
| `tests/<id>-<n>-*.tftest.hcl` | 44 | One step's spec test, named after its milestone | Each one asserts what one milestone adds, and each names its brief. They grade the build; they do not test the product. |
| `tests/scripts/` | 7 | Tests of the helper scripts, plus a fake GitHub CLI | They test tooling that is leaving. |
| `tests/fixtures/` | 1 | A saved run log for those tests | Only those tests read it. |

**What stays.**

| Path | Why it stays |
|---|---|
| `*.tf`, `modules/` (24 `.tf` files, and the Lambda sources beside them) | The product: buckets, table, policies, API, functions, queues, rules, alarms, dashboard. |
| `tests/root.tftest.hcl` | A test of the product: the root module wires all five modules and guards its inputs. Rename it from `tests/m0.tftest.hcl`, and rewrite its first comment so the file no longer names a milestone. |
| `docs/architecture.md` | The design, for a reader. |
| `docs/decisions.md` | The decision log. |
| `evidence/` | What the end-to-end run proved. |
| `README.md` | The front page. |
| `LICENSE` | What a reader may do with the code. |
| `.github/workflows/ci.yml` | The normal workflow. |
| `terraform.tfvars.example`, `backend.hcl.example`, `.gitignore`, `.gitattributes`, `.tflint.hcl` | How to run it, and the repository hygiene that keeps secrets out. |

The line between the two tables is the job of a file, not its extension. A test that names a milestone step, or a brief, is a grader: it exists to tell a learner what that step must add, and it goes. A test that asserts what the stack does, with no step in it, is a test of the product, and it stays. On this tree that is the root module's test alone; a test you wrote during the build that tests the router's edge cases stays with it, and the ship check's graders rule is what tells the two apart.

**Then scrub what stays.** Deleting the files is not enough: comments in the code still talk to a builder. Search the files that stay for a milestone ID (`M0`, `A1` to `A4`, `B1` to `B3`, `C1` to `C3`, `D1` to `D4`, `INT`), for the word `milestone`, for `PLACEHOLDER`, for `Portion `, and for the three phrases `Checkpoint`, `Done when`, and `you will`. Replace each with a sentence that would make sense to a reader who never saw the build, or delete the line. Three places to expect: the `# Portion X:` headers in the module files, the `PLACEHOLDER` notes on the module outputs, and the note in `.tflint.hcl` above the last lint rule. Keep every argument and every value as it is; this step changes words, not behavior.

That last note needs its own decision, because it is not only wording. The rule under it, `terraform_unused_declarations`, is on in a finished tree: INT turned it on, and every module reads the inputs it declares, so `tflint` reports nothing. Ship it that way. If `tflint` still reports an unused declaration, the declaration is real and it goes. Leave the rule off only in a tree where a module declares inputs that nothing reads, and then the one line above it says exactly that, as a fact about this tree, with no promise about a later step.

**The ship check.** `scripts/ship-check.sh` is the check for this step. It ships with the milestone like every other check in this repository: the tooling under `scripts/` is lead-owned, so you run it rather than write it. It reads the tree and fails while anything below is still there:

| Rule | What it looks for |
|---|---|
| Scaffolding | Any path in the "What leaves" table above, as a file or a directory. |
| Graders | Any file under `tests/` that still names a brief (`docs/milestones`), a step (`step 1`, `step 2`), or a `Brief:` line. A `*.check` file is a grader by definition. |
| Learner text | `Checkpoint`, `Done when`, `you will`, `milestone`, `PLACEHOLDER`, `Portion `, and a milestone ID, in any file that stays. |
| Local paths | A path that only exists on one machine: a home-folder shortcut, a folder under the home directory, a notes folder's name, and the scaffold's folder name. |
| Secrets | An AWS access key ID, a private-key header, a GitHub token, or an `aws_secret_access_key` assignment. |
| Loose ends | `TODO` and `FIXME`. |
| Missing anchors | `README.md`, `docs/architecture.md`, `docs/decisions.md`, `LICENSE`, and `evidence/README.md` must exist: a repository that lost its front page is worse than one with a stale note. |

It prints one line per problem, then a count, and exits 1. When the tree is clean it prints one line and exits 0. It skips `.git/`, `.terraform*`, `node_modules/`, `scripts/`, and `.github/scripts/`, because the last commit removes those and a check cannot ask for what it is about to delete. It reads the tree it is run in, and takes an optional directory argument, so its own tests can run it on a fixture.

**Run it before you delete anything.** It must fail, and its list is the work: everything it names is something to remove or rewrite. Paste that list into the pull request; it is the "before" half of the proof. Then delete, scrub, and run it again until it prints:

```
SHIP: clean. No scaffolding, learner text, local paths, or secrets.
```

The "after" half goes into the pull request too, next to the product tests' result.

**The last two commits, exactly.**

1. `chore(ship): remove the build scaffolding` deletes every path in the first table and scrubs the files that stay. After it, the ship check passes. The milestone runner is still in the tree, but it can no longer run: its ledger and its briefs are gone.
2. `chore(ship): retire the milestone runner` deletes `scripts/` and `.github/scripts/`, the last of the machinery. The normal workflow, committed in Part 4, is what runs from here on.

Order matters: the ship check passes while the runner is still present, and the final commit is the one that removes it. A reader of the history sees the removal and the cleanup as two steps, which is what they were.

Do **not** add `SHIP` to `milestones.txt`. This pull request deletes that file, and the branch name is what made CI check this milestone. The "SHIP is ready" issue, if one was opened, gets closed by hand after the merge, because the workflow that closed those issues is gone too. History is not rewritten on the way there: the commits keep their order and their content, nothing is rebased onto a new root, and no force push lands on `main`. The repository squashes the pull request when it merges, and that squash is the only rewrite; Done-when's last block is the count that proves it.

**Tags:** not applicable (this part deletes files and rewrites comments).

**Docs:** [GitHub: about repository licenses](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-license-on-a-repository) · [Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)

> **✅ Checkpoint: step 5 (the removal)**
> Run the milestone check one last time before you touch anything. Every numbered step must be ✅, because this is the last moment the check can run at all:
> ```bash
> scripts/check-local.sh
> ```
> Then run the ship check and keep its output; it fails on purpose and its list is the work:
> ```bash
> scripts/ship-check.sh
> ```
> Delete the paths in the first table, scrub the files that stay, and run it again until it prints `SHIP: clean. No scaffolding, learner text, local paths, or secrets.` The local check runs once here, before anything is deleted, because this part removes the command itself; after the first commit there is nothing left for it to read. Then commit the two steps separately:
> ```bash
> git add -A && git commit -m "chore(ship): remove the build scaffolding"
> git add -A && git commit -m "chore(ship): retire the milestone runner" && git push
> ```
> The push runs the normal workflow. It must be green: if it is red, the removed files were load-bearing, and the failure names what to put back.

## Check it

### How to see your results

The check runs in three places during this milestone, and the third one is new.

`scripts/check-local.sh` runs the milestone check on your machine at every checkpoint, and A1's [How to see your results](A1.md#how-to-see-your-results) explains that screen. GitHub runs the same check on every push to `ship`, up to and including step 4; results are on the run's page under **Actions** and on your pull request. From step 4 on, the push runs the **normal workflow** instead: formatting, validation, lint, the secret scan, and `terraform test`, and its result is the one that matters.

**After a push (automatic):** open the repository on GitHub, click **Actions**, click the newest run, and open the job log. The steps are in order, and the first red one names the command that failed.

**From your terminal:**

```bash
gh run watch --exit-status
```

This follows the newest run on your branch and exits non-zero if it fails. Before step 4 you can still use `scripts/remote-check.sh`, which prints the milestone summary in the shape the earlier briefs show.

When steps 1 to 4 are done, the check itself ends like this (this is the run on a tree with the four steps written, before the removal):

```
SHIP: 4 of 4 steps done
  ✅ formatting, init, validate
  ✅ step 1 (architecture)
  ✅ step 2 (readme)
  ✅ step 3 (proof)
  ✅ step 4 (workflow)

👍 SHIP passed.
```

`scripts/check-local.sh` adds one line above the blank one, `✅ earlier milestones still pass (...)`, with whatever `milestones.txt` holds on your branch, so yours will name the milestones that have merged.

SHIP runs in five steps. Steps 1 to 4 are checked by the milestone runner; step 5 is checked by `scripts/ship-check.sh`:

| Step | File | Checks |
|---|---|---|
| 1 (architecture) | `docs/architecture.md` | title, five section headings, the Mermaid flowchart, a DynamoDB status row, the file-key contract, the link to the decision log |
| 2 (readme) | `README.md` | the badge, seven section headings, links to the architecture note and the evidence, a `bash` block, the product-test command |
| 3 (proof) | `LICENSE`, `docs/decisions.md`, `evidence/README.md` | MIT, a dated decision table, the run link and the scan verdict |
| 4 (workflow) | `.github/workflows/ci.yml` | `push` and `pull_request`, the checkout and the setup steps, `init`, formatting, `validate`, `tflint --init` and `--recursive`, the secret scan, `terraform test` |
| the removal | the whole tree | `scripts/ship-check.sh` prints `SHIP: clean.` |

Every milestone already listed in `milestones.txt` is re-checked too, so a red row can name an earlier milestone: `scripts/check-local.sh <that milestone>` works on it alone. When a gate row is ❌ or the step table never appears, the `Next:` line names the gate that failed and prints the check's own message; for `formatting` it lists the files `terraform fmt` would change. See A1's [Check it](A1.md#check-it) for how to read each kind of failure.

The check reads text and Terraform. It cannot tell whether a stranger understands the README, whether the evidence is honest, or whether the workflow is green on GitHub. Those are what the next section and your reviewer are for.

## What this brief cannot verify

The check runs on your machine and reads text and Terraform. Two kinds of claim are left to a command: anything about your GitHub account, and anything about the Terraform binary the workflow installs. Each is marked "unverified" where it appears above; this table is the short list.

| Claim | The command that settles it |
|---|---|
| The workflow is green on `main` | `gh run list --workflow ci.yml --limit 5`, with the newest `main` run `completed  success` |
| `gh repo edit` and `gh repo view` accept these flags | `gh repo edit --help` |
| The repository is pinned | your profile page, **Customize your pins**; `gh` has no pin command |
| The product tests pass under the `terraform` binary the workflow installs | in the fresh clone, `terraform init -backend=false -input=false && terraform test -no-color`. The repository's own check runs under OpenTofu on a machine without Terraform (`TF=tofu`), and `tofu test` is a different binary from the `terraform test` the workflow runs at `terraform_version: "1.16.6"`, so a green `tofu` run does not prove this one |
| `terraform plan` and `terraform apply` work against your account | `terraform plan -detailed-exitcode` after an apply: exit 0, no changes |
| The README is clear to a stranger | hand it to someone who has not seen the build and ask the four questions in Part 2 |

## Done when (a fresh clone, and the repository page)

This milestone needs no AWS account. The blocks do not all run in the same tree or at the same moment, so each one says where it runs: one on your branch before the merge, four on `main` after it. The two that need GitHub are marked "unverified" here, with the command that settles each.

| Block | Where it runs | When |
|---|---|---|
| 1 | your branch | before you merge |
| 2 | a fresh clone of `main` | after the merge |
| 3 | `main`, on GitHub | after the merge |
| 4 | `main`, on GitHub | after the merge |
| 5 | `main`, in any clone | after the merge |

**Block 1: on your branch, the two commits are there and the runner is gone.**

```bash
git log --oneline --grep='chore(ship):' -3
git show --stat "$(git log --format=%H --grep='remove the build scaffolding' -1)" | sed -n '1,14p'
ls scripts .github/scripts 2>&1
```

Expected: two commits, the runner's retirement at the top and the removal under it. The removal's file list shows the briefs, the step tests, and `.github/workflows/next.yml` as deleted. `ls` reports that `scripts` and `.github/scripts` do not exist. The ship check's "before" list and its "clean" line are in the pull request, and that is the only place they can be read: the script leaves with this branch.

**Block 2: after the merge, a fresh clone builds from the README alone.** Run this on `main`: `git clone` with no `-b` gives you `main`, which is what a stranger gets, and `main` carries the milestone only after the merge. Clone into an empty folder, so nothing from your working copy helps, and follow only what the README says. From that folder:

```bash
git clone https://github.com/umbra-codex/aws-secure-file-upload ~/ship-check-clone
cd ~/ship-check-clone
cp terraform.tfvars.example terraform.tfvars    # fill in project_name, owner, alert_email
cp backend.hcl.example backend.hcl              # set bucket to your state bucket's name
terraform init -backend-config=backend.hcl      # needs your state bucket; use -backend=false to stay offline
terraform validate
terraform test
```

Expected: `terraform validate` prints `Success! The configuration is valid.` and `terraform test` runs every remaining `*.tftest.hcl` and prints `Success! N passed, 0 failed.` Both are offline once the providers are cached. `terraform plan` and `terraform apply` need your AWS credentials and your state bucket: they are not part of this check. The command that proves them is `terraform plan -detailed-exitcode` in that folder, which must exit 0 with no changes after an apply.

**Block 3: after the merge, the workflow is green.** On GitHub, **Actions** shows the newest run on `main` for **ci** with a green check, and its steps are the checkout and the two setup steps, formatting, the init step, validation, lint, the secret scan, and the tests. Unverified in this brief; the command that settles it is `gh run list --workflow ci.yml --limit 5`, which must show the newest run on `main` as `completed  success`.

**Block 4: after the merge, the repository page says what it is.** The license line comes from the file on the default branch, so this block waits for the merge too. Set the description and the topics, then check all three:

```bash
gh repo edit umbra-codex/aws-secure-file-upload \
  --description "Serverless file upload pipeline: GuardDuty malware scanning, real type and size checks, and a clean/quarantine split, in Terraform" \
  --add-topic aws,terraform,serverless,s3,lambda,guardduty,eventbridge,dynamodb,security
gh repo view umbra-codex/aws-secure-file-upload --json description,repositoryTopics,licenseInfo
```

Expected: the description, the nine topics, and `"licenseInfo": {"name": "MIT License"}`. Both commands are unverified in this brief: `gh repo edit --help` prints the flags your version accepts, and the `gh repo view` line is what settles the result. Then pin the repository: on your GitHub profile page, **Customize your pins**, and tick it. Pinning has no command in `gh`; the page is the only place to check it, so this one is unverified too.

**Block 5: after the merge, the squash added exactly one commit and moved nothing else.** Before you merge, on `main` and after a `git pull`, run `git rev-list --count main` and write the number down. Then, after the merge, in any clone of `main`:

```bash
git checkout main && git pull
git rev-list --count main
git log --oneline -1 main
git log --oneline main | tail -3
```

Expected: exactly one more commit than the number you wrote down. The repository squashes, so the commits on your branch land as one commit whose subject is the pull request's title, and that squash is the only rewrite: no force push, and no earlier commit on `main` changed, so the last three lines are the same three commits as before. A count that did not go up means the merge never happened; a count that went up by more than one means the repository's merge setting is not what M0 records.

Things that commonly go wrong:

- **`terraform test` fails after the removal** with a missing file: a `*.tftest.hcl` that named a brief is still there. The ship check lists it under `graders`; delete it, or rewrite it so it asserts the stack instead of a step.
- **The workflow fails on `terraform validate` after the removal** with "Unsupported attribute": a removed file was holding a value the configuration reads, which should be impossible. Read the error; it names the file and the attribute.
- **The ship check reports `learner text` on a line you cannot find**: it prints the file and the line number. Open that line and look for one of the words in the rule table; it is usually a comment carried over from the build.
- **The ship check reports `secret` on a line that is documentation**: a sentence that spells out a token shape trips the same rule a real token would. Reword the sentence; do not weaken the check.
- **The badge is red on `main`**: the badge reads the newest run of the `ci` workflow. If the workflow file's `name` changed, the badge URL no longer matches, and the badge shows "no status".
- **`gh repo edit --add-topic` refuses the list**: pass the flag once per topic instead (`--add-topic aws --add-topic terraform`). Which form your version accepts is unverified here; `gh repo edit --help` settles it.

Before you mark it ready, on your branch, check `git status --short`: it must be empty, and `git log --oneline -3` must show, newest first, the runner's retirement, the removal, and the workflow commit. Then retitle the pull request to the whole milestone and mark it ready (see A1's [Mark the pull request ready](A1.md#mark-the-pull-request-ready)). The repo is squash-only, so the PR's title becomes the commit on `main`:

```bash
gh pr edit --title "chore(ship): ship the repository"
gh pr ready
```

A teammate approves, and it merges. After the merge, close the "SHIP is ready" issue by hand if one was opened, set the repository's social preview image if you have one, and check the pinned card on your profile. The project is done.
