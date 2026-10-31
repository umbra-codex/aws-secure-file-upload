output "incoming_bucket_name" {
  description = "Bucket that receives raw uploads."
  value       = module.incoming.bucket_name
}

output "incoming_bucket_arn" {
  description = "ARN of the Incoming bucket."
  value       = module.incoming.bucket_arn
}

output "approved_bucket_name" {
  description = "Bucket that holds clean, validated files"
  value       = module.approved.bucket_name
}

output "approved_bucket_arn" {
  description = "ARN of the Approved bucket."
  value       = module.approved.bucket_arn
}

output "quarantine_bucket_name" {
  description = "Bucket that holds rejected files."
  value       = module.quarantine.bucket_name
}

output "quarantine_bucket_arn" {
  description = "ARN of the Quarantine bucket."
  value       = module.quarantine.bucket_arn
}

output "table_name" {
  description = "Name of the uploads DynamoDB"
  value       = aws_dynamodb_table.uploads.name
}

output "table_arn" {
  description = "ARN of the uploads DynamoDB table."
  value       = aws_dynamodb_table.uploads.arn
}
