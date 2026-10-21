# A1 step 2: modules/storage/bucket/main.tf
# The bucket and its settings. Brief: docs/milestones/A1.md

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

run "bucket_basics" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name = "unit-test-bucket"
    tags        = { Name = "unit-test-bucket", Role = "unit", ManagedBy = "terraform" }
  }

  # Pin an ID that differs from the name, so a resource that types the name
  # instead of referencing the bucket fails.
  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "mock-bucket-id"
      arn = "arn:aws:s3:::unit-test-bucket"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "unit-test-bucket"
    error_message = "aws_s3_bucket.this must take its bucket name from the bucket_name variable (got ${aws_s3_bucket.this.bucket})."
  }

  assert {
    condition     = aws_s3_bucket.this.tags == tomap(var.tags)
    error_message = "aws_s3_bucket.this must take its tags from the tags variable (got ${jsonencode(aws_s3_bucket.this.tags)})."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls &&
      aws_s3_bucket_public_access_block.this.block_public_policy &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets
    )
    error_message = "aws_s3_bucket_public_access_block.this must set all four settings to true."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.bucket == aws_s3_bucket.this.id
    error_message = "aws_s3_bucket_public_access_block.this must reference the bucket's id, not a typed name (got ${aws_s3_bucket_public_access_block.this.bucket})."
  }

  # Exactly one rule that declares AES256. Counting matters: alltrue([]) is true.
  assert {
    condition = length(aws_s3_bucket_server_side_encryption_configuration.this.rule) == 1 && alltrue([
      for r in aws_s3_bucket_server_side_encryption_configuration.this.rule :
      length(r.apply_server_side_encryption_by_default) == 1 &&
      one([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm]) == "AES256"
    ])
    error_message = "aws_s3_bucket_server_side_encryption_configuration.this needs exactly one rule whose apply_server_side_encryption_by_default sets sse_algorithm = \"AES256\"."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.bucket == aws_s3_bucket.this.id
    error_message = "The encryption configuration must reference the bucket's id (got ${aws_s3_bucket_server_side_encryption_configuration.this.bucket})."
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0 && length(aws_s3_bucket_cors_configuration.this) == 0
    error_message = "By default (enable_versioning = false, no CORS origins) the module must create no versioning and no CORS resource. Use count."
  }
}

run "bucket_versioned" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name       = "unit-test-bucket"
    enable_versioning = true
  }

  # Pin an ID that differs from the name, so a resource that types the name
  # instead of referencing the bucket fails.
  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "mock-bucket-id"
      arn = "arn:aws:s3:::unit-test-bucket"
    }
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 1
    error_message = "With enable_versioning = true, exactly one aws_s3_bucket_versioning.this must exist."
  }

  assert {
    condition     = one([for c in aws_s3_bucket_versioning.this[0].versioning_configuration : c.status]) == "Enabled"
    error_message = "aws_s3_bucket_versioning.this must set status = \"Enabled\"."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this[0].bucket == aws_s3_bucket.this.id
    error_message = "aws_s3_bucket_versioning.this must reference the bucket's id (got ${aws_s3_bucket_versioning.this[0].bucket})."
  }
}

run "bucket_cors_one_origin" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name          = "unit-test-bucket"
    cors_allowed_origins = ["http://localhost:3000"]
  }

  # Pin an ID that differs from the name, so a resource that types the name
  # instead of referencing the bucket fails.
  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "mock-bucket-id"
      arn = "arn:aws:s3:::unit-test-bucket"
    }
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 1
    error_message = "With cors_allowed_origins set, exactly one aws_s3_bucket_cors_configuration.this must exist."
  }

  assert {
    condition = length(aws_s3_bucket_cors_configuration.this[0].cors_rule) == 1 && alltrue([
      for r in aws_s3_bucket_cors_configuration.this[0].cors_rule :
      toset(r.allowed_methods) == toset(["POST"]) && toset(r.allowed_origins) == toset(["http://localhost:3000"])
    ])
    error_message = "The CORS configuration needs one cors_rule allowing only POST, from exactly the origins in cors_allowed_origins."
  }

  assert {
    condition     = aws_s3_bucket_cors_configuration.this[0].bucket == aws_s3_bucket.this.id
    error_message = "The CORS configuration must reference the bucket's id (got ${aws_s3_bucket_cors_configuration.this[0].bucket})."
  }
}

run "bucket_cors_two_origins" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name          = "unit-test-bucket"
    cors_allowed_origins = ["http://localhost:3000", "https://app.example.com"]
  }

  assert {
    condition = length(aws_s3_bucket_cors_configuration.this) == 1 && length(aws_s3_bucket_cors_configuration.this[0].cors_rule) == 1 && alltrue([
      for r in aws_s3_bucket_cors_configuration.this[0].cors_rule :
      toset(r.allowed_origins) == toset(["http://localhost:3000", "https://app.example.com"])
    ])
    error_message = "With two origins there must still be one CORS configuration with one rule listing both origins (not one rule per origin)."
  }
}
