variable "project_name" {
  description = "Prefix for resource names."
  type        = string
}

variable "incoming_bucket_name" {
  description = "Name of the Incoming bucket."
  type        = string
}

variable "incoming_bucket_arn" {
  description = "ARN of the Incoming bucket."
  type        = string
}

variable "router_lambda_arn" {
  description = "ARN of Lambda 2 (router), the scan-result rule's target."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the alerts topic."
  type        = string
}
