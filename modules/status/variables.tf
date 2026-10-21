variable "project_name" {
  description = "Prefix for resource names."
  type        = string
}

variable "table_name" {
  description = "Name of the uploads DynamoDB table."
  type        = string
}

variable "table_arn" {
  description = "ARN of the uploads DynamoDB table."
  type        = string
}

variable "api_id" {
  description = "ID of the HTTP API (from upload_api) that the status route attaches to."
  type        = string
}

variable "api_execution_arn" {
  description = "Execution ARN of the HTTP API, for the Lambda invoke permission."
  type        = string
}
