# Portion C: Scanning and Events

**Owner:** @rizuanul90 · **Module:** `modules/scanning/` (wired in `scanning.tf`) · **Milestones:** C1, C2, C3

Back to [the project overview](../overview.md) for the architecture, shared contracts, and schedule.

## What you own

The security core. You turn on GuardDuty's malware scanning for the Incoming bucket, route every scan result to Lambda 2, catch anything EventBridge can't deliver, and email the team when malware shows up or the scanner breaks.

## Milestones

| PR | Branch | Build | Depends on | Done when (in your account) |
|---|---|---|---|---|
| C1 | `c1-guardduty` | `aws_guardduty_malware_protection_plan` on Incoming, scoped to the `uploads/` prefix, with object tagging on, plus its IAM role | A1 | The plan status is `ACTIVE`; an uploaded file gets a scan-result tag |
| C2 | `c2-scan-rule` | The scan-result EventBridge rule targeting Lambda 2, an explicit retry policy, the target DLQ with its queue policy, and the Lambda permission | C1, D1 | An upload produces a Lambda 2 log line containing its `upload_id` |
| C3 | `c3-alerts` | The alerts SNS topic with its topic policy and an email subscription, an alert rule, and an alarm on DLQ depth | C2 | Uploading the EICAR test file sends an email |

Briefs: [C1](../milestones/C1.md) · [C2](../milestones/C2.md) · [C3](../milestones/C3.md). Every push to your branch runs the check on GitHub; `scripts/remote-check.sh` re-runs it on demand.

## GuardDuty facts you build on

These come from the AWS docs, not memory:

- **Malware Protection for S3 runs as an independent feature.** It needs no GuardDuty detector, so it won't clash with a teammate who already has GuardDuty on. With no detector, malware produces no GuardDuty finding; the EventBridge event and the object tag are the signal.
- **Every scan result goes to the default EventBridge bus** with `source: aws.guardduty` and `detail-type: GuardDuty Malware Protection Object Scan Result`.
- **The result is in `detail.scanResultDetails.scanResultStatus`:** `NO_THREATS_FOUND`, `THREATS_FOUND`, `UNSUPPORTED` (skipped, e.g. password-protected), `ACCESS_DENIED` (skipped, e.g. SSE-C), or `FAILED`.
- **When the plan itself breaks,** GuardDuty sends `GuardDuty Malware Protection Resource Status Error`.
- **The plan's IAM role:** copy the trust policy and permissions from AWS's "Adding IAM policy permissions" page for Malware Protection for S3. It includes the object-tagging permission. Don't write it from memory.
- **GuardDuty can't scan SSE-C objects,** which is why the project uses SSE-S3.

## Rules for the rule (C2)

- **Event pattern:** `source` = `aws.guardduty` and `detail-type` = `GuardDuty Malware Protection Object Scan Result`.
- **Retry policy, set explicitly:** about 2 retry attempts and 300 seconds max event age, so failures surface in minutes instead of hours.
- **Target DLQ:** an SQS queue with a queue policy that allows `events.amazonaws.com` to `sqs:SendMessage`, with `aws:SourceArn` set to your rule's ARN. Terraform does not add this policy for you, and without it failed events vanish silently.
- **Lambda permission:** principal `events.amazonaws.com`, with `source_arn` set to the rule's ARN (not the function's). It lives in your module, next to the rule.

The target DLQ only catches events EventBridge couldn't deliver (missing permission, deleted function, throttling). If Lambda 2 runs and throws an error, that lands in D's `router-failures` queue instead. The two queues cover different failures, and the project needs both.

## Alerts (C3)

- One SNS topic with an email subscription to `alert_email`. Each person confirms their subscription email after `apply`.
- A topic policy allowing `events.amazonaws.com` to `sns:Publish`, with `aws:SourceArn` set to the alert rule, and a second statement allowing `cloudwatch.amazonaws.com` to `sns:Publish`, with `aws:SourceArn` set to the DLQ alarm.
- One alert rule matching scan results with `THREATS_FOUND`, plus `GuardDuty Malware Protection Resource Status Error` events. The two events have different shapes, so the pattern uses `$or` (see [C3](../milestones/C3.md)).
- A CloudWatch alarm when the target DLQ holds any message. It publishes to the alerts topic when it enters `ALARM`, so the same address is emailed.

## Your interface

| Outputs (others depend on these) | Inputs |
|---|---|
| `guardduty_role_arn`, `guardduty_plan_id` (C1); `scan_rule_arn`, `dlq_arn`, `dlq_name` (C2; B's dashboard reads `dlq_name`); `alerts_topic_arn`, `alert_rule_name`, `alarm_names` (C3) | `project_name`, `incoming_bucket_name/arn`, `router_lambda_arn` (from D1), `alert_email` |

## Your permissions

| Role or policy | Grants | Resource |
|---|---|---|
| GuardDuty plan role | the seven statements of the policy in the AWS doc (no KMS statement: our buckets use SSE-S3) | Incoming bucket |
| DLQ queue policy | `events.amazonaws.com` → `sqs:SendMessage`, only from the scan rule | the DLQ |
| alerts topic policy | `events.amazonaws.com` → `sns:Publish`, only from the alert rule; `cloudwatch.amazonaws.com` → `sns:Publish`, only from the DLQ alarm | the topic |

## Well-Architected items you deliver

- **Use managed services / Democratize advanced technologies:** GuardDuty scans files instead of a scanner the team runs itself (C1).
- **Understand your impact:** scanning only the `uploads/` prefix (C1).
- **Automatically recover from failure:** retries plus the DLQ, so undelivered events are captured (C2).
- **Prepare for security events:** malware and scanner-error alerts (C3).
