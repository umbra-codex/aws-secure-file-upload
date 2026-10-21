# A2 step 1: expiration in modules/storage/bucket (variables.tf, main.tf, outputs.tf)
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

run "bucket_no_expiration_by_default" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name = "unit-test-bucket"
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
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0 && output.expiration_days == null
    error_message = "With expiration_days left at null, the module must create no aws_s3_bucket_lifecycle_configuration (use count), and output expiration_days must be null."
  }
}

run "bucket_expiration" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name       = "unit-test-bucket"
    enable_versioning = true
    expiration_days   = 7
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
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 1
    error_message = "With expiration_days set, exactly one aws_s3_bucket_lifecycle_configuration.this must exist."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this[0].bucket == aws_s3_bucket.this.id
    error_message = "The lifecycle configuration must reference the bucket's id (got ${aws_s3_bucket_lifecycle_configuration.this[0].bucket})."
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule) == 1 &&
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].status == "Enabled" &&
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter) == 1
    )
    error_message = "The lifecycle configuration needs exactly one rule with status = \"Enabled\" and an empty filter block (so it applies to every object)."
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration) == 1 &&
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration[0].days == 7
    )
    error_message = "The rule's expiration block must set days from the expiration_days variable."
  }

  assert {
    condition = (
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration) == 1 &&
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 7
    )
    error_message = "The rule's noncurrent_version_expiration block must set noncurrent_days from the expiration_days variable, so old versions expire too."
  }

  assert {
    condition     = output.expiration_days == 7
    error_message = "Output expiration_days must reference the expiration_days variable."
  }
}
