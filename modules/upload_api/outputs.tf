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
  value       = aws_iam_role.upload_url.arn
}

output "upload_function_name" {
  description = "Name of Lambda 1 (upload-url)."
  value       = aws_lambda_function.upload_url.function_name
}