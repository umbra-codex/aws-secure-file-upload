variable "project_name" {
  description = "Prefix for resource names."
  type        = string
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to POST to the Incoming bucket. Empty = no CORS rule."
  type        = list(string)
}

variable "router_role_arn" {
  description = "ARN of Lambda 2's (router) IAM role. Used by the Quarantine bucket policy in A3."
  type        = string
}
