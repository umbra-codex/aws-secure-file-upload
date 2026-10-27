resource "aws_dynamodb_table" "uploads" {
  name         = "${var.project_name}-uploads"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "upload_id"

  attribute {
    name = "upload_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name      = "${var.project_name}-uploads"
    Role      = "uploads"
    ManagedBy = "terraform"
  }
}
