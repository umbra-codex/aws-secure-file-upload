output "incoming_bucket_name" {
  description = "Name of the Incoming bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "placeholder-incoming"
}

output "incoming_bucket_arn" {
  description = "ARN of the Incoming bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "arn:aws:s3:::placeholder-incoming"
}

output "approved_bucket_name" {
  description = "Name of the Approved bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "placeholder-approved"
}

output "approved_bucket_arn" {
  description = "ARN of the Approved bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "arn:aws:s3:::placeholder-approved"
}

output "quarantine_bucket_name" {
  description = "Name of the Quarantine bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "placeholder-quarantine"
}

output "quarantine_bucket_arn" {
  description = "ARN of the Quarantine bucket."
  # PLACEHOLDER: replace with a reference to the real resource in A1.
  value = "arn:aws:s3:::placeholder-quarantine"
}

output "table_name" {
  description = "Name of the uploads DynamoDB table."
  # PLACEHOLDER: replace with a reference to the real resource in A2.
  value = "placeholder-uploads"
}

output "table_arn" {
  description = "ARN of the uploads DynamoDB table."
  # PLACEHOLDER: replace with a reference to the real resource in A2.
  value = "arn:aws:dynamodb:us-east-1:000000000000:table/placeholder-uploads"
}
