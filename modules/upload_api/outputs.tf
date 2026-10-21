output "api_url" {
  description = "Base URL of the HTTP API."
  # PLACEHOLDER: replace with a reference to the real resource in B2.
  value = "https://placeholder.execute-api.us-east-1.amazonaws.com"
}

output "api_id" {
  description = "ID of the HTTP API."
  # PLACEHOLDER: replace with a reference to the real resource in B2.
  value = "placeholder-api-id"
}

output "api_execution_arn" {
  description = "Execution ARN of the HTTP API."
  # PLACEHOLDER: replace with a reference to the real resource in B2.
  value = "arn:aws:execute-api:us-east-1:000000000000:placeholder-api-id"
}

output "upload_role_arn" {
  description = "ARN of Lambda 1's IAM role."
  # PLACEHOLDER: replace with a reference to the real resource in B1.
  value = "arn:aws:iam::000000000000:role/placeholder-upload"
}
