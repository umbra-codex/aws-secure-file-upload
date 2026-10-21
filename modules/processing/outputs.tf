output "router_lambda_arn" {
  description = "ARN of Lambda 2 (router)."
  # PLACEHOLDER: replace with a reference to the real resource in D1.
  value = "arn:aws:lambda:us-east-1:000000000000:function:placeholder-router"
}

output "router_function_name" {
  description = "Function name of Lambda 2 (router)."
  # PLACEHOLDER: replace with a reference to the real resource in D1.
  value = "placeholder-router"
}

output "router_role_arn" {
  description = "ARN of Lambda 2's IAM role."
  # PLACEHOLDER: replace with a reference to the real resource in D1.
  value = "arn:aws:iam::000000000000:role/placeholder-router"
}

output "router_failures_queue_name" {
  description = "Name of Lambda 2's on-failure SQS queue."
  # PLACEHOLDER: replace with a reference to the real resource in D2.
  value = "placeholder-router-failures"
}

output "router_failures_queue_url" {
  description = "URL of Lambda 2's on-failure SQS queue (used by scripts/redrive.sh)."
  # PLACEHOLDER: replace with a reference to the real resource in D2.
  value = "https://sqs.us-east-1.amazonaws.com/000000000000/placeholder-router-failures"
}
