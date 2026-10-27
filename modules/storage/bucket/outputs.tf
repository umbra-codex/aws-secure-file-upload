output "bucket_id" {
  description = "ID of the bucket (the same as its name in AWS)."
  value       = aws_s3_bucket.this.id
}

output "bucket_name" {
  description = "Name of the bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket."
  value       = aws_s3_bucket.this.arn
}

output "tags" {
  description = "Tags on the bucket, including the Name tag."
  value       = aws_s3_bucket.this.tags
}

output "versioning_enabled" {
  description = "Whether versioning was turned on."
  value       = length(aws_s3_bucket_versioning.this) > 0
}

output "cors_enabled" {
  description = "Whether a CORS configuration was created."
  value       = length(aws_s3_bucket_cors_configuration.this) > 0
}

output "expiration_days" {
  description = "Days until objects expire, or null if they never do."
  value       = var.expiration_days
}
