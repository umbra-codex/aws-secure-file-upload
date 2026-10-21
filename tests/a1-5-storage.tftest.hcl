# A1 step 5: modules/storage/buckets.tf and modules/storage/outputs.tf
# Storage calls the bucket module three times. Brief: docs/milestones/A1.md
# The mocked account ID (210987654321) differs from the docs' 123456789012,
# so a typed-in account ID fails.

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

run "storage_calls_the_module_three_times" {
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
    condition     = module.incoming.bucket_name == "demo-210987654321-incoming"
    error_message = "module \"incoming\" must name its bucket <project_name>-<account_id>-incoming (expected demo-210987654321-incoming, got ${module.incoming.bucket_name}). The account ID must come from aws_caller_identity."
  }

  assert {
    condition     = module.approved.bucket_name == "demo-210987654321-approved"
    error_message = "module \"approved\" must name its bucket <project_name>-<account_id>-approved (got ${module.approved.bucket_name})."
  }

  assert {
    condition     = module.quarantine.bucket_name == "demo-210987654321-quarantine"
    error_message = "module \"quarantine\" must name its bucket <project_name>-<account_id>-quarantine (got ${module.quarantine.bucket_name})."
  }

  # S3's naming rule: 3-63 characters; lowercase letters, numbers, dots and
  # hyphens; starting and ending with a letter or number; no "..".
  assert {
    condition = alltrue([
      for n in [module.incoming.bucket_name, module.approved.bucket_name, module.quarantine.bucket_name] :
      length(n) >= 3 && length(n) <= 63 && can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", n)) && !strcontains(n, "..")
    ])
    error_message = "Every bucket name must follow S3's naming rule: 3-63 characters, lowercase letters, numbers, dots and hyphens, starting and ending with a letter or number."
  }

  assert {
    condition = alltrue([
      for m in [
        { t = module.incoming.tags, name = "demo-210987654321-incoming", role = "incoming" },
        { t = module.approved.tags, name = "demo-210987654321-approved", role = "approved" },
        { t = module.quarantine.tags, name = "demo-210987654321-quarantine", role = "quarantine" },
      ] :
      lookup(m.t, "Name", "") == m.name && lookup(m.t, "Role", "") == m.role && lookup(m.t, "ManagedBy", "") == "terraform"
    ])
    error_message = "Each module call must pass tags with Name = the bucket's name, Role = incoming/approved/quarantine, and ManagedBy = \"terraform\" (incoming got ${jsonencode(module.incoming.tags)})."
  }

  assert {
    condition     = module.incoming.versioning_enabled && !module.approved.versioning_enabled && !module.quarantine.versioning_enabled
    error_message = "Versioning must be on for Incoming only (incoming=${module.incoming.versioning_enabled}, approved=${module.approved.versioning_enabled}, quarantine=${module.quarantine.versioning_enabled})."
  }

  assert {
    condition     = !module.incoming.cors_enabled && !module.approved.cors_enabled && !module.quarantine.cors_enabled
    error_message = "With cors_allowed_origins = [], no bucket may have CORS."
  }

  assert {
    condition     = output.incoming_bucket_name == module.incoming.bucket_name && output.incoming_bucket_arn == "arn:aws:s3:::demo-210987654321-incoming"
    error_message = "incoming_bucket_name / incoming_bucket_arn must reference module.incoming's bucket_name and bucket_arn (got ${output.incoming_bucket_name} / ${output.incoming_bucket_arn})."
  }

  assert {
    condition     = output.approved_bucket_name == module.approved.bucket_name && output.approved_bucket_arn == "arn:aws:s3:::demo-210987654321-approved"
    error_message = "approved_bucket_name / approved_bucket_arn must reference module.approved's bucket_name and bucket_arn (got ${output.approved_bucket_name} / ${output.approved_bucket_arn})."
  }

  assert {
    condition     = output.quarantine_bucket_name == module.quarantine.bucket_name && output.quarantine_bucket_arn == "arn:aws:s3:::demo-210987654321-quarantine"
    error_message = "quarantine_bucket_name / quarantine_bucket_arn must reference module.quarantine's bucket_name and bucket_arn (got ${output.quarantine_bucket_name} / ${output.quarantine_bucket_arn})."
  }
}

run "storage_cors_only_on_incoming" {
  module {
    source = "./modules/storage"
  }

  variables {
    project_name         = "demo"
    cors_allowed_origins = ["http://localhost:3000"]
    router_role_arn      = "arn:aws:iam::210987654321:role/demo-router"
  }

  assert {
    condition     = module.incoming.cors_enabled && !module.approved.cors_enabled && !module.quarantine.cors_enabled
    error_message = "cors_allowed_origins must be passed to the Incoming module only (incoming=${module.incoming.cors_enabled}, approved=${module.approved.cors_enabled}, quarantine=${module.quarantine.cors_enabled})."
  }
}
