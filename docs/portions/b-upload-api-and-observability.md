# Portion B: Upload API and Observability

**Owner:** (unassigned) · **Module:** `modules/upload_api/` (wired in `upload_api.tf`) · **Code:** `modules/upload_api/src/` · **Milestones:** B1, B2, B3

Back to [the project overview](../overview.md) for the architecture, shared contracts, and schedule.

## What you own

The front door and the dashboard. Clients ask your API for an upload URL; your Lambda decides whether the request is allowed, records it, and hands back a presigned POST that only works for one key, one size range, and 15 minutes. At the end you build the CloudWatch dashboard and alarms the whole team watches.

## Milestones

| PR | Branch | Build | Depends on | Done when (in your account) |
|---|---|---|---|---|
| B1 | `b1-upload-lambda` | Lambda 1 code, the `arm64` function (10-second timeout), its role, and a 14-day log group; structured JSON logs that include `upload_id` | A1, A2 | A test invoke from the console returns a presigned POST and writes a `PENDING` row |
| B2 | `b2-api` | HTTP API with `POST /upload-url` → Lambda 1, access logging to a 14-day log group, and the presigned POST conditions below | B1 | `curl` gets a URL; uploading with it lands at the expected key; an oversize upload is rejected by S3 |
| B3 | `b3-observability` | API throttling, API CORS, one CloudWatch dashboard, and Lambda error alarms | B2, C2, D2 | The dashboard shows a test upload; a forced Lambda error flips an alarm |

Briefs: [B1](../milestones/B1.md) · [B2](../milestones/B2.md) · [B3](../milestones/B3.md). Every push to your branch runs the check on GitHub; `scripts/remote-check.sh` re-runs it on demand.

## What Lambda 1 does

1. Read the requested filename, content type, and size.
2. Reject the request if the type isn't in `allowed_types` or the size is over `max_size_mb`.
3. Generate `upload_id` as a UUID.
4. Clean the filename: strip `/`, `..`, and control characters, and cap the length.
5. Write the row: `upload_id`, `filename`, `declared_type`, `declared_size`, `status = PENDING`, `created_at`, and `expires_at` = now + presign expiry + 1 hour (epoch seconds). The full layout is in the overview's DynamoDB contract.
6. Return a presigned POST for the Incoming bucket with these conditions:
   - the key is exactly `uploads/{upload_id}/{safe_filename}` (boto3 adds this condition when it's given the key)
   - `content-length-range` from 1 byte to `max_size_mb`
   - a 15-minute expiry

The presigned POST is signed with Lambda 1's own role, which is why that role needs `s3:PutObject` on `uploads/*` even though Lambda 1 never uploads anything itself.

## The dashboard (B3)

One dashboard showing:

- GuardDuty scan results by status (GuardDuty publishes these as CloudWatch metrics)
- Lambda 1 and Lambda 2 errors and duration
- the depth of both failure queues (`dlq_name` from C and `router_failures_queue_name` from D)
- API 4xx and 5xx counts

## Your interface

| Outputs (others depend on these) | Inputs |
|---|---|
| `upload_role_arn` (B1); `api_url`, `api_id`, `api_execution_arn` (B2; A4 attaches the status route to your API) | `project_name`, `incoming_bucket_name/arn`, `table_name/arn`, `allowed_types`, `max_size_mb`; for B3: `router_function_name`, `dlq_name`, `router_failures_queue_name` |

## Your permissions

| Role | Actions | Resource |
|---|---|---|
| upload role | `s3:PutObject` | `incoming/uploads/*` |
| upload role | `dynamodb:PutItem` | the table |
| upload role | `logs:CreateLogStream`, `logs:PutLogEvents` | its log group |

API Gateway also needs permission to invoke Lambda 1 (a Lambda permission scoped to your API's execution ARN).

## Well-Architected items you deliver

- **Implement a strong identity foundation / Maintain traceability:** a least-privilege role and logs that carry `upload_id` (B1); API access logs (B2).
- **Apply security at all layers:** presigned POST limits (B2) and throttling (B3).
- **Consider mechanical sympathy:** files go straight to S3 and never pass through your API or Lambda (B2).
- **Implement observability for actionable insights:** the dashboard (B3).
- **Anticipate and adopt new, more efficient offerings:** `arm64` (B1).
