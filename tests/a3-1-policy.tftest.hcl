# A3 step 1: the bucket policy in modules/storage/bucket (variables.tf, main.tf, outputs.tf)
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

run "bucket_policy_denies_insecure_transport" {
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
    condition     = length(data.aws_iam_policy_document.this.statement) == 1
    error_message = "With allowed_reader_arn left at null, the policy document must have exactly one statement (DenyInsecureTransport)."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.this.statement : st
      if st.sid == "DenyInsecureTransport" && st.effect == "Deny" &&
      toset(st.actions) == toset(["s3:*"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::unit-test-bucket", "arn:aws:s3:::unit-test-bucket/*"])
    ]) == 1
    error_message = "Statement DenyInsecureTransport must Deny actions [\"s3:*\"] on both the bucket ARN and the bucket ARN followed by /*."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.this.statement :
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "*" && toset(p.identifiers) == toset(["*"])]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "Bool" && c.variable == "aws:SecureTransport" && toset(c.values) == toset(["false"])])
      if st.sid == "DenyInsecureTransport"
    ])
    error_message = "Statement DenyInsecureTransport needs one principals block (type \"*\", identifiers [\"*\"]) and one condition (test \"Bool\", variable \"aws:SecureTransport\", values [\"false\"])."
  }

  assert {
    condition     = aws_s3_bucket_policy.this.bucket == aws_s3_bucket.this.id && aws_s3_bucket_policy.this.policy == data.aws_iam_policy_document.this.json
    error_message = "aws_s3_bucket_policy.this must reference the bucket's id and the policy document's json."
  }

  assert {
    condition     = output.allowed_reader_arn == null
    error_message = "Output allowed_reader_arn must reference the allowed_reader_arn variable."
  }
}

run "bucket_policy_with_reader_lock" {
  module {
    source = "./modules/storage/bucket"
  }

  variables {
    bucket_name        = "unit-test-bucket"
    allowed_reader_arn = "arn:aws:iam::210987654321:role/demo-router"
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
    condition     = length(data.aws_iam_policy_document.this.statement) == 2
    error_message = "With allowed_reader_arn set, the policy document must have two statements: DenyInsecureTransport and DenyReadsExceptAllowedReader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.this.statement : st
      if st.sid == "DenyReadsExceptAllowedReader" && st.effect == "Deny" &&
      toset(st.actions) == toset(["s3:GetObject", "s3:GetObjectVersion"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::unit-test-bucket/*"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "*" && toset(p.identifiers) == toset(["*"])]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "StringNotEquals" && c.variable == "aws:PrincipalArn" && toset(c.values) == toset(["arn:aws:iam::210987654321:role/demo-router"])])
    ]) == 1
    error_message = "Statement DenyReadsExceptAllowedReader must Deny s3:GetObject and s3:GetObjectVersion on the bucket ARN followed by /*, for principal type \"*\" identifiers [\"*\"], with condition StringNotEquals aws:PrincipalArn = the allowed_reader_arn variable."
  }

  assert {
    condition     = output.allowed_reader_arn == "arn:aws:iam::210987654321:role/demo-router"
    error_message = "Output allowed_reader_arn must reference the allowed_reader_arn variable."
  }
}
