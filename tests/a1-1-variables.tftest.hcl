# A1 step 1: modules/storage/bucket/variables.tf
# The four inputs exist, with the right defaults. Brief: docs/milestones/A1.md

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

run "variables_have_their_defaults" {
  command = plan

  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name = "unit-test-bucket"
  }

  assert {
    condition     = var.bucket_name == "unit-test-bucket"
    error_message = "The bucket_name variable must exist and keep the value it's given."
  }

  assert {
    condition     = var.enable_versioning == false
    error_message = "enable_versioning must default to false."
  }

  assert {
    condition     = length(var.cors_allowed_origins) == 0
    error_message = "cors_allowed_origins must default to an empty list."
  }

  assert {
    condition     = length(var.tags) == 0
    error_message = "tags must default to an empty map."
  }
}

run "variables_accept_values" {
  command = plan

  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name          = "unit-test-bucket"
    enable_versioning    = true
    cors_allowed_origins = ["http://localhost:3000", "https://app.example.com"]
    tags                 = { Name = "unit-test-bucket", Role = "unit", ManagedBy = "terraform" }
  }

  assert {
    condition     = var.enable_versioning == true && length(var.cors_allowed_origins) == 2 && lookup(var.tags, "Role", "") == "unit"
    error_message = "enable_versioning (bool), cors_allowed_origins (list of strings) and tags (map of strings) must accept the values they're given."
  }
}
