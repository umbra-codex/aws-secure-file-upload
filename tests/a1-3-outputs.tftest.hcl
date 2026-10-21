# A1 step 3: modules/storage/bucket/outputs.tf
# Each output points at the right attribute. Brief: docs/milestones/A1.md

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

run "outputs_without_options" {
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
    condition     = output.bucket_id == aws_s3_bucket.this.id && output.bucket_name == aws_s3_bucket.this.bucket && output.bucket_arn == aws_s3_bucket.this.arn
    error_message = "Outputs bucket_id, bucket_name and bucket_arn must reference aws_s3_bucket.this's id, bucket and arn."
  }

  assert {
    condition     = output.tags == aws_s3_bucket.this.tags
    error_message = "Output tags must reference aws_s3_bucket.this's tags."
  }

  assert {
    condition     = output.versioning_enabled == false && output.cors_enabled == false
    error_message = "versioning_enabled and cors_enabled must be false when versioning and CORS weren't created."
  }
}

run "outputs_with_options" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name          = "unit-test-bucket"
    enable_versioning    = true
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
    condition     = output.versioning_enabled == true && output.cors_enabled == true
    error_message = "versioning_enabled and cors_enabled must be true when versioning and CORS were created."
  }
}
