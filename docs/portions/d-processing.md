# Portion D: Processing

**Owner:** (unassigned) · **Module:** `modules/processing/` (wired in `processing.tf`) · **Code:** `lambdas/router/`, `scripts/redrive.sh` · **Milestones:** D1, D2, D3, D4

Back to [the project overview](../overview.md) for the architecture, shared contracts, and schedule.

## What you own

The decision-maker. Lambda 2 receives every GuardDuty scan result, runs its own checks, moves the file to Approved or Quarantine, and records the outcome. This is the most code in the project, and the place where small mistakes become security bugs, so the rules below are strict on purpose.

## Milestones

| PR | Branch | Build | Depends on | Done when (in your account) |
|---|---|---|---|---|
| D1 | `d1-router-lambda` | The router role, the `arm64` function (30-second timeout), and a 14-day log group; the function logs the event it receives | A1, A2 | A test invoke with AWS's sample scan-result event logs it |
| D2 | `d2-routing` | The routing table, copy-by-version and delete-by-version, the conditional DynamoDB update, the `router-failures` queue with an on-failure destination, and `scripts/redrive.sh` | D1 | Synthetic test: seed a `PENDING` row, upload a file to `uploads/{id}/`, invoke with a sample event carrying that key and version. The file is in Approved, that version is gone from Incoming, and the row says `APPROVED` |
| D3 | `d3-validation` | Your own checks: magic bytes, real size, allowed types; failures go to Quarantine with `INVALID_TYPE` or `TOO_LARGE` | D2 | A `.png` that's really an `.exe` lands in Quarantine with `INVALID_TYPE` |
| D4 | `d4-idempotency` | Edge cases (no row → log and drop; version gone → `STALE`) and memory right-sized from logged durations | D3 | Invoking twice with the same event changes nothing; an unknown key logs and returns success |

The brief for each milestone will be in the repo at `docs/milestones/<ID>.md`. Every push to your branch runs the check on GitHub; `scripts/remote-check.sh` re-runs it on demand. D2's done-when uses a synthetic event so it doesn't wait on C's GuardDuty work.

## Routing table

Every outcome except one goes to Quarantine. Your own checks can only demote a clean file, never promote a flagged one.

| `scanResultStatus` | Meaning | Route |
|---|---|---|
| `NO_THREATS_FOUND` | Clean | Approved, if your own checks also pass; otherwise Quarantine with `INVALID_TYPE` or `TOO_LARGE` |
| `THREATS_FOUND` | Malware | Quarantine |
| `UNSUPPORTED` | Skipped, e.g. password-protected | Quarantine |
| `ACCESS_DENIED` | Skipped, e.g. SSE-C encrypted | Quarantine |
| `FAILED` | Scan failed | Quarantine |

## Rules Lambda 2 must follow

- **Find the row from the key.** The key is `uploads/{upload_id}/{filename}`; take `upload_id` from the second segment. S3's own event notifications percent-encode keys, and it isn't confirmed whether GuardDuty's events do, so log a real event's `objectKey` for a filename with a space in D1 and decode it in D2 if needed.
- **Copy by version.** Use the event's `versionId` in `CopySource`, and delete that same version from Incoming. Otherwise a client who overwrites the key after the scan sneaks unscanned bytes into Approved.
- **Order: copy, then delete, then update DynamoDB.** The DynamoDB write goes last, so a crash anywhere earlier leaves a `PENDING` row that a retry can finish.
- **Conditional update.** Write the result with the condition `attribute_exists(upload_id) AND #s = :pending`. A replayed event then changes nothing, and it can't recreate a deleted row.
- **Keep finished rows.** The same update also removes `expires_at` (`REMOVE expires_at`), so DynamoDB's TTL only deletes uploads that never finished and `GET /status` keeps answering for finished ones. (Umbra's decision, 2026-10-21.)
- **Version already gone:** set `QUARANTINED` with reason `STALE` and return success. Don't retry it.
- **No matching row** (a console upload, a leftover object): log it and return success. Raising an error would just retry it into the failure queue.
- **Magic bytes in plain code.** Don't use `python-magic`; its OS library isn't in the Lambda image. Read the first 16 bytes with a ranged `GetObject` and compare against a small table: PNG `89 50 4E 47`, JPEG `FF D8 FF`, PDF `25 50 44 46`, ZIP `50 4B 03 04`. A Windows executable starts with `4D 5A` (`MZ`) and always fails.
- **Move files server-side** with `CopyObject`. Never download and re-upload.

## Failure handling

EventBridge invokes Lambda 2 asynchronously. Once Lambda accepts an event, an error in your code is retried by Lambda, not EventBridge, so C's DLQ never sees it. Your on-failure destination is what catches it:

- `aws_lambda_function_event_invoke_config` with `maximum_retry_attempts = 1` and `on_failure` pointing at the `router-failures` SQS queue.
- Your role needs `sqs:SendMessage` on that queue.
- Each failure record carries the original event as `requestPayload`.

`scripts/redrive.sh` reads `router-failures`, re-invokes Lambda 2 with each `requestPayload`, and deletes the message once the invoke succeeds. INT test 6 exercises exactly this path.

## Your interface

| Outputs (others depend on these) | Inputs |
|---|---|
| `router_lambda_arn`, `router_function_name`, `router_role_arn` (D1; C targets your function, A3's policy names your role); `router_failures_queue_name/url` (D2; B's dashboard and the redrive script use them) | `project_name`, all 3 buckets' name/arn, `table_name/arn`, `allowed_types`, `max_size_mb` |

## Your permissions

| Actions | Resource |
|---|---|
| `s3:GetObject`, `s3:GetObjectVersion`, `s3:GetObjectTagging`, `s3:GetObjectVersionTagging` | `incoming/*` |
| `s3:DeleteObjectVersion` | `incoming/*` |
| `s3:PutObject`, `s3:PutObjectTagging` | `approved/*`, `quarantine/*` |
| `dynamodb:GetItem`, `dynamodb:UpdateItem` | the table |
| `sqs:SendMessage` | `router-failures` |
| `logs:CreateLogStream`, `logs:PutLogEvents` | your log group |

## Well-Architected items you deliver

- **Maintain traceability:** logs carrying `upload_id`, and the row recording the version scanned and its destination (D1, D2).
- **Automatically recover from failure:** the on-failure queue and redrive (D2).
- **Consider mechanical sympathy:** a 16-byte ranged read and server-side copy (D2, D3).
- **Apply security at all layers:** your own type and size checks behind GuardDuty's (D3).
- **Maximize utilization:** memory set from measured duration (D4).
