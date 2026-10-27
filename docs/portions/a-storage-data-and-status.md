# Portion A: Storage, Data, and Status

**Owner:** Sean (@umbra-codex) · **Modules:** `modules/storage/` (wired in `storage.tf`), its reusable `modules/storage/bucket/` submodule, and `modules/status/` (wired in `status.tf`) · **Milestones:** A1, A2, A3, A4

Back to [the project overview](../overview.md) for the architecture, shared contracts, and schedule.

## What you own

The data layer every other portion depends on: the three S3 buckets, the DynamoDB table of upload records, the bucket policies that keep people away from the files, and the `GET /status/{upload_id}` endpoint the client polls. Your A1 and A2 outputs unblock everyone else in week 1, so they come first.

## Design: one bucket module, called three times

The three buckets are identical apart from a few settings, so they come from one reusable module, `modules/storage/bucket/`, following HashiCorp's [module creation pattern](https://developer.hashicorp.com/terraform/tutorials/recommended-patterns/pattern-module-creation). The module holds everything that always comes with a bucket (Block Public Access, encryption, the bucket policy) and has four on/off inputs for what differs:

| Module call | `enable_versioning` | `cors_allowed_origins` | `expiration_days` | `allowed_reader_arn` |
|---|---|---|---|---|
| `incoming` | `true` | passed through | `1` | (none) |
| `approved` | (default `false`) | (none) | (none) | (none) |
| `quarantine` | (default `false`) | (none) | `30` | the router role |

The pattern advises avoiding conditionals in a first module; these four are simple on/off switches because the three buckets need different settings, and each one is tested both ways.

## Milestones

| PR | Branch | Build | Depends on | Done when (in your account) |
|---|---|---|---|---|
| A1 | `a1-buckets` | The bucket module (bucket, Block Public Access, SSE-S3, optional versioning and CORS, a README) and three calls to it named `<project>-<account_id>-<role>`; versioning and CORS on Incoming only | M0 | `apply` creates all 3; uploading a test file to `uploads/` in Incoming works; versioning reports `Enabled` |
| A2 | `a2-table` | Expiration in the bucket module (Incoming 1 day including old versions, Quarantine 30); the DynamoDB table (on-demand, point-in-time recovery, TTL on `expires_at`) | A1 | The table exists with PITR on; lifecycle rules show on both buckets |
| A3 | `a3-bucket-policies` | A bucket policy in the module (deny non-TLS on every bucket; optional read lock), with Quarantine locked to the router role | A1, D1 | D2's synthetic test still passes after A3 is applied; reading from Quarantine as your admin user is denied |
| A4 | `a4-status` | Status Lambda, its role and log group, and the `GET /status/{upload_id}` route on B's API | A2, B2 | `curl` returns `PENDING` for a row whose `expires_at` is in the future, `EXPIRED` for one in the past, and `404` for an unknown id |

Briefs: [A1](../milestones/A1.md) · [A2](../milestones/A2.md) · [A3](../milestones/A3.md) · [A4](../milestones/A4.md). Every push to your branch runs the check on GitHub; `scripts/remote-check.sh` re-runs it on demand.

## Rules for your resources

- **Bucket names** use the account ID from `aws_caller_identity`, never a typed value.
- **Versioning stays on Incoming only.** Lambda 2 copies the exact object version GuardDuty scanned, which only works on a versioned bucket. The A1 check verifies this through each bucket's `versioning_enabled` output.
- **CORS** is one rule on Incoming allowing only `POST` from exactly the configured origins, created with `count` so it disappears when the list is empty.
- **The table's partition key** is `upload_id` (String). TTL uses `expires_at` (epoch seconds), which Lambda 1 writes. The full item layout is in the overview's DynamoDB contract.
- **`EXPIRED` is computed by the status Lambda at read time:** if the row says `PENDING` and `expires_at` has passed, return `EXPIRED`. TTL deletes rows in the background later, so nothing waits on it.
- **The status Lambda** is `arm64`, 5-second timeout, with a 14-day log group created in Terraform.
- **The status route** attaches to B's HTTP API using the `api_id` and `api_execution_arn` inputs. Your Lambda needs an invoke permission scoped to that API.
- **The cycle rule:** storage takes `router_role_arn` from processing for the A3 policy. No storage output may be computed from it, or `plan` fails with a cycle between storage and processing.

## Your interface

| Module | Outputs (others depend on these) | Inputs |
|---|---|---|
| storage | `incoming_bucket_name/arn`, `approved_bucket_name/arn`, `quarantine_bucket_name/arn` (A1); `table_name/arn` (A2) | `project_name`, `cors_allowed_origins`, `router_role_arn` (from D1, used in A3) |
| status | `status_role_arn`, `status_function_name`, `status_route_key` (A4) | `project_name`, `table_name/arn`, `api_id`, `api_execution_arn` (from B2) |

## Your permissions

| Role or policy | Grants or denies | Resource |
|---|---|---|
| status role | allow `dynamodb:GetItem` | the table |
| status role | allow `logs:CreateLogStream`, `logs:PutLogEvents` | its log group |
| all 3 bucket policies | deny any request where `aws:SecureTransport` is false | each bucket |
| Quarantine bucket policy | deny `s3:GetObject` and `s3:GetObjectVersion` unless `aws:PrincipalArn` is the router role | Quarantine |

## Well-Architected items you deliver

- **Protect data in transit and at rest:** SSE-S3 (A1) and the non-TLS deny (A3).
- **Keep people away from data:** the Quarantine read deny (A3).
- **Test recovery procedures / Stop guessing capacity:** point-in-time recovery and on-demand capacity on the table (A2).
- **Use managed services (sustainability):** lifecycle rules (A2).

## Also yours

- M0 (done) and every milestone brief and test, as the lead.
- The README's "file was quarantined, now what" runbook and the final diagram, during INT.
