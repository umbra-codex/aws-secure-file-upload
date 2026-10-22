# Portion D: Processing

**Owner:** @blaborte · **Module:** `modules/processing/` (wired in `processing.tf`) · **Code:** `modules/processing/src/`, `scripts/redrive.sh` · **Milestones:** D1, D2, D3, D4

Back to [the project overview](../overview.md) for the architecture, shared contracts, and schedule.

## What you own

The decision-maker. Lambda 2 receives every GuardDuty scan result, runs its own checks, moves the file to Approved or Quarantine, and records the outcome. This is the most code in the project, and the place where small mistakes become security bugs, so the rules below are strict on purpose.

## Milestones

| PR | Branch | Build | Depends on | Done when (in your account) |
|---|---|---|---|---|
| D1 | `d1-router-lambda` | The router role (logging only), the `arm64` function (30-second timeout), and a 14-day log group; the function logs the event it receives | A1, A2 | A test invoke with AWS's sample scan-result event logs it |
| D2 | `d2-routing` | The routing table, copy-by-version, the conditional DynamoDB update, delete-by-version, the six data permissions, the `router-failures` queue with an on-failure destination, and `scripts/redrive.sh` | D1 | Synthetic test: seed a `PENDING` row, upload a file to `uploads/{id}/`, invoke with a sample event carrying that key and version. The file is in Approved, that version is gone from Incoming, and the row says `APPROVED`. Then break the row update on purpose, see the failure land in the queue, repair it, and replay with `scripts/redrive.sh` |
| D3 | `d3-validation` | Your own checks: magic bytes, real size, allowed types; failures go to Quarantine with `INVALID_TYPE` or `TOO_LARGE` | D2 | A `.png` that's really an `.exe` lands in Quarantine with `INVALID_TYPE` |
| D4 | `d4-idempotency` | Edge cases (no row → log and drop; row not `PENDING` → delete the leftover; version gone → `STALE`) and memory right-sized from logged durations | D3 | Invoking twice with the same event changes nothing; an unknown key logs and returns success |

Briefs: [D1](../milestones/D1.md) · [D2](../milestones/D2.md) · [D3](../milestones/D3.md) · [D4](../milestones/D4.md). Every push to your branch runs the check on GitHub; `scripts/remote-check.sh` re-runs it on demand. Every "Done when" uses a synthetic event, so none of it waits on C's GuardDuty work. D2 changes `scripts/`, which is lead-owned, so its pull request needs the lead's approval too.

## Routing table

Every outcome except one goes to Quarantine. Your own checks can only demote a clean file, never promote a flagged one.

| `scanResultStatus` | Meaning | Route |
|---|---|---|
| `NO_THREATS_FOUND` | Clean | Approved, if your own checks also pass; otherwise Quarantine with `TOO_LARGE` or `INVALID_TYPE` |
| `THREATS_FOUND` | Malware | Quarantine |
| `UNSUPPORTED` | Skipped, e.g. password-protected | Quarantine |
| `ACCESS_DENIED` | Skipped, e.g. SSE-C encrypted | Quarantine |
| `FAILED` | Scan failed | Quarantine |

`NO_THREATS_FOUND` is the only value that opens the door to Approved. Any other value, including one AWS adds later, falls through to Quarantine with the status as the reason.

## Rules Lambda 2 must follow

- **Find the row from the key, and rebuild the key from the row.** The key is `uploads/{upload_id}/{filename}`; take `upload_id` from the second segment, read the row, and rebuild the key from the row's cleaned `filename`. AWS's docs don't say whether GuardDuty's events percent-encode `objectKey` the way S3's own notifications do; rebuilding the key means it never matters.
- **Copy by version.** Use the event's `versionId` in `CopySource`, and delete that same version from Incoming. Otherwise a client who overwrites the key after the scan sneaks unscanned bytes into Approved.
- **Order: copy, then update DynamoDB, then delete.** A crash after the copy leaves a `PENDING` row that a retry finishes. A crash after the update leaves a finished row and a leftover scanned version, which a retry deletes (see the next rules). Deleting before updating would be worse: a crash between them leaves a `PENDING` row whose version is gone, and the retry would mark a good file `STALE`.
- **Conditional update.** Write the result with the condition `attribute_exists(upload_id) AND #s = :pending`. A replayed event then changes nothing, and it can't recreate a deleted row.
- **Keep finished rows.** The same update also removes `expires_at` (`REMOVE expires_at`), so DynamoDB's TTL only deletes uploads that never finished and `GET /status` keeps answering for finished ones. (Umbra's decision, 2026-10-21.)
- **Row not `PENDING`** (a replay, or a second event for the same upload): delete the scanned version, copy nothing, and return success. A replay never overwrites an approved file.
- **Version already gone:** set `QUARANTINED` with reason `STALE` (and no `destination_bucket`, since nothing was copied) and return success. Don't retry it. S3 reports a missing version as `NoSuchVersion` or `NoSuchKey`, and a HEAD request as plain `404`; any other error code is a real problem and is raised.
- **No matching row** (a console upload, a leftover object): log it and return success. Raising an error would just retry it into the failure queue.
- **Magic bytes in plain code.** Don't use `python-magic`; its OS library isn't in the Lambda image. Read the first 16 bytes with a ranged `GetObject` and compare against a small table: PNG `89 50 4E 47`, JPEG `FF D8 FF`, PDF `25 50 44 46`, ZIP `50 4B 03 04`. A Windows executable starts with `4D 5A` (`MZ`) and always fails. The detected type must be in `ALLOWED_TYPES`; the row's `declared_type` is never compared.
- **Real size.** Ask S3 with `HeadObject` on the scanned version, not the row's `declared_size`. Check the size before the type, so a file that is both too big and the wrong type is reported as `TOO_LARGE`.
- **Move files server-side** with `CopyObject`. Never download and re-upload.

## Failure handling

EventBridge invokes Lambda 2 asynchronously. Once Lambda accepts an event, an error in your code is retried by Lambda, not EventBridge, so C's DLQ never sees it. Your on-failure destination is what catches it:

- `aws_lambda_function_event_invoke_config` with `maximum_retry_attempts = 1` and `on_failure` pointing at the `router-failures` SQS queue.
- Your role needs `sqs:SendMessage` on that queue, and the destination waits for that permission (`depends_on`).
- Each failure record carries the original event as `requestPayload`.

`scripts/redrive.sh` reads `router-failures`, re-invokes Lambda 2 with each `requestPayload`, and deletes the message once the invoke succeeds. INT test 6 exercises exactly this path.

## Your interface

| Outputs (others depend on these) | Inputs |
|---|---|
| `router_lambda_arn`, `router_function_name`, `router_role_arn` (D1; C targets your function, A3's policy names your role); `router_failures_queue_name/url` (D2; B's dashboard and the redrive script use them; the root also exposes the URL) | `project_name`, all 3 buckets' name/arn, `table_name/arn`, `allowed_types`, `max_size_mb` |

## Your permissions

D1 gives the role the last row. D2 adds the rest as a second policy.

| Actions | Resource |
|---|---|
| `s3:GetObject`, `s3:GetObjectVersion`, `s3:GetObjectTagging`, `s3:GetObjectVersionTagging` | `incoming/*` |
| `s3:ListBucket` | the Incoming bucket itself. Without it, S3 answers a missing object with 403 instead of 404, and "the version is gone" can't be told from "not allowed" |
| `s3:DeleteObjectVersion` | `incoming/*` |
| `s3:PutObject`, `s3:PutObjectTagging` | `approved/*`, `quarantine/*` |
| `dynamodb:GetItem`, `dynamodb:UpdateItem` | the table |
| `sqs:SendMessage` | `router-failures` |
| `logs:CreateLogStream`, `logs:PutLogEvents` | your log group |

## Well-Architected items you deliver

- **Maintain traceability:** logs carrying `upload_id`, and the row recording the version scanned and its destination (D1, D2).
- **Automatically recover from failure:** the on-failure queue and redrive (D2), and a handler that is safe to run twice (D4).
- **Consider mechanical sympathy:** a 16-byte ranged read and server-side copy (D2, D3).
- **Apply security at all layers:** your own type and size checks behind GuardDuty's (D3).
- **Maximize utilization:** memory set from measured duration (D4).
