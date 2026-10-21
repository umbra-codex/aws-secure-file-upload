# A2 step 2: expiration on the module calls in modules/storage/buckets.tf
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

run "storage_expiration" {
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

  assert {
    condition     = module.incoming.expiration_days == 1 && module.approved.expiration_days == null && module.quarantine.expiration_days == 30
    error_message = "Expiration must be 1 day on Incoming, 30 days on Quarantine, and none on Approved."
  }
}
