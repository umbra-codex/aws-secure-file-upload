# A3 step 2: the Quarantine read lock in modules/storage/buckets.tf
# Brief: docs/milestones/A3.md

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

run "storage_locks_quarantine_only" {
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
    condition     = module.quarantine.allowed_reader_arn == "arn:aws:iam::210987654321:role/demo-router"
    error_message = "module \"quarantine\" must pass the router_role_arn variable as allowed_reader_arn."
  }

  assert {
    condition     = module.incoming.allowed_reader_arn == null && module.approved.allowed_reader_arn == null
    error_message = "Only Quarantine gets a reader lock. Incoming and Approved must leave allowed_reader_arn unset."
  }
}
