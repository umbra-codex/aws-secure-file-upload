# Inputs of the bucket module. Declared in A1 (see docs/milestones/A1.md).
variable "bucket_name" {
  description = "Full, globally unique bucket name."
  type        = string
}

variable "enable_versioning" {
  description = "Turn on object versioning."
  type        = bool
  default     = false
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to POST. Empty = no CORS configuration."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for the bucket: at least Name, Role, and ManagedBy."
  type        = map(string)
  default     = {}
}
