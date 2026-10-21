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

variable "table_name" {
  description = "Name of the uploads DynamoDB table."
  type        = string
}

variable "table_arn" {
  description = "ARN of the uploads DynamoDB table."
  type        = string
}

variable "allowed_types" {
  description = "MIME types the pipeline accepts."
  type        = list(string)
}

variable "max_size_mb" {
  description = "Largest upload accepted, in MB."
  type        = number
}

variable "router_function_name" {
  description = "Lambda 2's function name, for the dashboard and alarms (B3)."
  type        = string
}

variable "dlq_name" {
  description = "EventBridge target DLQ name, for the dashboard (B3)."
  type        = string
}

variable "router_failures_queue_name" {
  description = "Lambda 2 on-failure queue name, for the dashboard (B3)."
  type        = string
}
