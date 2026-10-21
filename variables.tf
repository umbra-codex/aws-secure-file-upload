variable "project_name" {
  description = "Prefix for every resource name. Lowercase letters, numbers, and hyphens; 3-20 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-20 characters: lowercase letters, numbers, and hyphens, not starting or ending with a hyphen."
  }
}

variable "owner" {
  description = "Your name or GitHub handle. Goes into the Owner tag on every resource."
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", var.region))
    error_message = "region must look like us-east-1 (no spaces, no availability-zone letter)."
  }
}

variable "allowed_types" {
  description = "MIME types the pipeline accepts."
  type        = list(string)
  default     = ["image/png", "image/jpeg", "application/pdf"]

  validation {
    condition     = length(var.allowed_types) > 0 && alltrue([for t in var.allowed_types : can(regex("^[a-z]+/[a-z0-9.+-]+$", t))])
    error_message = "allowed_types must be a non-empty list of MIME types like image/png (lowercase, no spaces)."
  }
}

variable "max_size_mb" {
  description = "Largest upload accepted, in MB."
  type        = number
  default     = 25

  validation {
    condition     = var.max_size_mb >= 1 && var.max_size_mb <= 100
    error_message = "max_size_mb must be between 1 and 100."
  }
}

variable "alert_email" {
  description = "Email address that receives malware and pipeline alerts (you must confirm the SNS subscription email)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to POST to the Incoming bucket. Empty means no CORS rule (fine for curl testing)."
  type        = list(string)
  default     = []
}
