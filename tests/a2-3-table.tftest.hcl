# A2 step 3: modules/storage/dynamodb.tf and the table outputs
# Brief: docs/milestones/A2.md

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  # A3 adds a bucket policy built from this data source. The mock would fake
  # its JSON with random text, which the bucket policy rejects.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "uploads_table" {
  module {
    source = "./modules/storage"
  }

  variables {
    project_name         = "demo"
    cors_allowed_origins = []
    router_role_arn      = "arn:aws:iam::210987654321:role/demo-router"
  }

  override_resource {
    target = module.incoming.aws_s3_bucket.this
    values = {
      id  = "mock-id-incoming"
      arn = "arn:aws:s3:::demo-210987654321-incoming"
    }
  }

  override_resource {
    target = module.approved.aws_s3_bucket.this
    values = {
      id  = "mock-id-approved"
      arn = "arn:aws:s3:::demo-210987654321-approved"
    }
  }

  override_resource {
    target = module.quarantine.aws_s3_bucket.this
    values = {
      id  = "mock-id-quarantine"
      arn = "arn:aws:s3:::demo-210987654321-quarantine"
    }
  }

  override_resource {
    target = aws_dynamodb_table.uploads
    values = {
      arn = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    }
  }

  assert {
    condition     = aws_dynamodb_table.uploads.name == "demo-uploads"
    error_message = "aws_dynamodb_table.uploads must be named <project_name>-uploads (expected demo-uploads, got ${aws_dynamodb_table.uploads.name})."
  }

  assert {
    condition     = aws_dynamodb_table.uploads.billing_mode == "PAY_PER_REQUEST"
    error_message = "The table must use billing_mode = \"PAY_PER_REQUEST\" (on-demand)."
  }

  assert {
    condition = (
      aws_dynamodb_table.uploads.hash_key == "upload_id" &&
      length(aws_dynamodb_table.uploads.attribute) == 1 &&
      alltrue([for a in aws_dynamodb_table.uploads.attribute : a.name == "upload_id" && a.type == "S"])
    )
    error_message = "The table's hash_key must be upload_id, declared by exactly one attribute block (name = \"upload_id\", type = \"S\")."
  }

  assert {
    condition = (
      length(aws_dynamodb_table.uploads.ttl) == 1 &&
      aws_dynamodb_table.uploads.ttl[0].enabled == true &&
      aws_dynamodb_table.uploads.ttl[0].attribute_name == "expires_at"
    )
    error_message = "The table needs a ttl block with attribute_name = \"expires_at\" and enabled = true."
  }

  assert {
    condition     = length(aws_dynamodb_table.uploads.point_in_time_recovery) == 1 && aws_dynamodb_table.uploads.point_in_time_recovery[0].enabled == true
    error_message = "The table needs a point_in_time_recovery block with enabled = true."
  }

  assert {
    condition = (
      lookup(aws_dynamodb_table.uploads.tags, "Name", "") == "demo-uploads" &&
      lookup(aws_dynamodb_table.uploads.tags, "Role", "") == "uploads" &&
      lookup(aws_dynamodb_table.uploads.tags, "ManagedBy", "") == "terraform"
    )
    error_message = "The table needs tags Name = <project_name>-uploads, Role = \"uploads\", and ManagedBy = \"terraform\" (got ${jsonencode(aws_dynamodb_table.uploads.tags)})."
  }

  assert {
    condition     = output.table_name == aws_dynamodb_table.uploads.name && output.table_arn == "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    error_message = "table_name / table_arn must reference aws_dynamodb_table.uploads (got ${output.table_name} / ${output.table_arn})."
  }
}
