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

variable "approved_bucket_name" {
  description = "Name of the Approved bucket."
  type        = string
}

variable "approved_bucket_arn" {
  description = "ARN of the Approved bucket."
  type        = string
}

variable "quarantine_bucket_name" {
  description = "Name of the Quarantine bucket."
  type        = string
}

variable "quarantine_bucket_arn" {
  description = "ARN of the Quarantine bucket."
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
