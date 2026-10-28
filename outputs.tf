output "api_url" {
  description = "Base URL of the upload API."
  value       = module.upload_api.api_url
}

output "incoming_bucket_arn" {
  description = "ARN of the Incoming bucket."
  value       = module.storage.incoming_bucket_arn
}

output "approved_bucket_arn" {
  description = "ARN of the Approved bucket."
  value       = module.storage.approved_bucket_arn
}

output "quarantine_bucket_arn" {
  description = "ARN of the Quarantine bucket."
  value       = module.storage.quarantine_bucket_arn
}

output "router_function_name" {
  description = "Lambda 2 (router) function name, for logs and redrive."
  value       = module.processing.router_function_name
}

output "incoming_bucket_name" {
  description = "Bucket that receives raw uploads."
  value       = module.storage.incoming_bucket_name
}

output "approved_bucket_name" {
  description = "Bucket that holds clean, validated files."
  value       = module.storage.approved_bucket_name
}

output "quarantine_bucket_name" {
  description = "Bucket that holds rejected files."
  value       = module.storage.quarantine_bucket_name
}

output "table_name" {
  description = "DynamoDB table of upload records."
  value       = module.storage.table_name
}

output "guardduty_plan_id" {
  description = "ID of the GuardDuty malware protection plan on the Incoming bucket."
  value       = module.scanning.guardduty_plan_id
}
