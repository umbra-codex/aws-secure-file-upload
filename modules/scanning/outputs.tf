output "guardduty_role_arn" {
  description = "ARN of the GuardDuty malware protection plan's IAM role."
  # PLACEHOLDER: replace with a reference to the real resource in C1.
  value = "arn:aws:iam::000000000000:role/placeholder-guardduty"
}

output "scan_rule_arn" {
  description = "ARN of the EventBridge scan-result rule."
  # PLACEHOLDER: replace with a reference to the real resource in C2.
  value = "arn:aws:events:us-east-1:000000000000:rule/placeholder-scan-result"
}

output "dlq_arn" {
  description = "ARN of the EventBridge target DLQ."
  # PLACEHOLDER: replace with a reference to the real resource in C2.
  value = "arn:aws:sqs:us-east-1:000000000000:placeholder-dlq"
}

output "dlq_name" {
  description = "Name of the EventBridge target DLQ."
  # PLACEHOLDER: replace with a reference to the real resource in C2.
  value = "placeholder-dlq"
}

output "alerts_topic_arn" {
  description = "ARN of the SNS alerts topic."
  # PLACEHOLDER: replace with a reference to the real resource in C3.
  value = "arn:aws:sns:us-east-1:000000000000:placeholder-alerts"
}
