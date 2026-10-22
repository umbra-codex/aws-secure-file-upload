# D2 step 3: modules/processing/iam.tf, the data permissions (a second document and policy).
# Brief: docs/milestones/D2.md
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  # A3 adds bucket policies built from this data source. The mock would fake
  # its JSON with random text, which the bucket policy rejects.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Resources other resources validate as ARNs or URLs. The mock would invent
  # random strings, so give every resource of these types a well-formed value.
  # (mock_resource needs no target, so this is safe before they exist.)
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::210987654321:role/mock-role"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:mock-function"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:mock-function/invocations"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:mock"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      arn           = "arn:aws:apigateway:us-east-1::/apis/mock-api"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:mock-api"
      api_endpoint  = "https://mock-api.execute-api.us-east-1.amazonaws.com"
    }
  }

  mock_resource "aws_apigatewayv2_stage" {
    defaults = {
      arn           = "arn:aws:apigateway:us-east-1::/apis/mock-api/stages/$default"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:mock-api/$default"
      invoke_url    = "https://mock-api.execute-api.us-east-1.amazonaws.com/"
    }
  }

  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/mock-rule"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:210987654321:mock-queue"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/mock-queue"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:210987654321:mock-topic"
    }
  }
}

run "router_data_access" {
  module {
    source = "./modules/processing"
  }

  variables {
    project_name           = "demo"
    incoming_bucket_name   = "demo-incoming-210987654321"
    incoming_bucket_arn    = "arn:aws:s3:::demo-incoming-210987654321"
    approved_bucket_name   = "demo-approved-210987654321"
    approved_bucket_arn    = "arn:aws:s3:::demo-approved-210987654321"
    quarantine_bucket_name = "demo-quarantine-210987654321"
    quarantine_bucket_arn  = "arn:aws:s3:::demo-quarantine-210987654321"
    table_name             = "demo-uploads"
    table_arn              = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    allowed_types          = ["image/png", "application/pdf"]
    max_size_mb            = 25
  }

  # The mock gives every resource of a type the same values. Pin distinct ones
  # so a reference to the wrong resource or attribute fails.
  override_resource {
    target = aws_iam_role.router
    values = {
      id  = "mock-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-router"
    }
  }

  override_resource {
    target = aws_sqs_queue.failures
    values = {
      id  = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-router-failures"
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-router-failures"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-router-failures"
    }
  }

  # The mock gives every policy document the same JSON, so a reference to the
  # wrong document would pass. Pin a distinct JSON for each one.
  override_data {
    target = data.aws_iam_policy_document.assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockAssume\"}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.permissions
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockPermissions\"}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.data_access
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockDataAccess\"}]}"
    }
  }

  assert {
    condition     = length(data.aws_iam_policy_document.data_access.statement) == 6
    error_message = "data.aws_iam_policy_document.data_access must have exactly six statements, the ones in the brief's table (got ${length(data.aws_iam_policy_document.data_access.statement)}). Nothing else: no wildcard actions, no s3:*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ReadIncoming" && st.effect == "Allow" && toset(st.actions) == toset(["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging", "s3:GetObjectVersionTagging"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ReadIncoming: Allow s3:GetObject, s3:GetObjectVersion, s3:GetObjectTagging and s3:GetObjectVersionTagging on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ListIncoming" && st.effect == "Allow" && toset(st.actions) == toset(["s3:ListBucket"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ListIncoming: Allow s3:ListBucket on the incoming_bucket_arn variable itself (no /*). Without it S3 answers a missing object with 403 instead of 404."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "DeleteScannedVersion" && st.effect == "Allow" && toset(st.actions) == toset(["s3:DeleteObjectVersion"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement DeleteScannedVersion: Allow s3:DeleteObjectVersion on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "WriteDestinations" && st.effect == "Allow" && toset(st.actions) == toset(["s3:PutObject", "s3:PutObjectTagging"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-approved-210987654321/*", "arn:aws:s3:::demo-quarantine-210987654321/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement WriteDestinations: Allow s3:PutObject and s3:PutObjectTagging on the approved and quarantine bucket ARN variables, each followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "UpdateRow" && st.effect == "Allow" && toset(st.actions) == toset(["dynamodb:GetItem", "dynamodb:UpdateItem"]) && toset(st.resources) == toset(["arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement UpdateRow: Allow dynamodb:GetItem and dynamodb:UpdateItem on the table_arn variable."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ReportFailures" && st.effect == "Allow" && toset(st.actions) == toset(["sqs:SendMessage"]) && toset(st.resources) == toset(["arn:aws:sqs:us-east-1:210987654321:demo-router-failures"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ReportFailures: Allow sqs:SendMessage on the arn of aws_sqs_queue.failures."
  }

  assert {
    condition     = aws_iam_role_policy.router_data.name == "demo-router-data" && aws_iam_role_policy.router_data.role == aws_iam_role.router.id && aws_iam_role_policy.router_data.policy == data.aws_iam_policy_document.data_access.json
    error_message = "aws_iam_role_policy.router_data must be named <project_name>-router-data and reference the role's id and the data_access document's json."
  }

  assert {
    condition     = aws_iam_role_policy.router.policy == data.aws_iam_policy_document.permissions.json
    error_message = "aws_iam_role_policy.router (D1's logging policy) must stay as it was: the permissions document's json."
  }
}

# Nothing in the permissions may be fixed text: give every ARN another value
# and every statement must follow.
run "data_access_follows_its_inputs" {
  module {
    source = "./modules/processing"
  }

  variables {
    project_name           = "other"
    incoming_bucket_name   = "other-incoming-111122223333"
    incoming_bucket_arn    = "arn:aws:s3:::other-incoming-111122223333"
    approved_bucket_name   = "other-approved-111122223333"
    approved_bucket_arn    = "arn:aws:s3:::other-approved-111122223333"
    quarantine_bucket_name = "other-quarantine-111122223333"
    quarantine_bucket_arn  = "arn:aws:s3:::other-quarantine-111122223333"
    table_name             = "other-uploads"
    table_arn              = "arn:aws:dynamodb:us-east-1:111122223333:table/other-uploads"
    allowed_types          = ["image/jpeg"]
    max_size_mb            = 5
  }

  override_resource {
    target = aws_sqs_queue.failures
    values = {
      arn = "arn:aws:sqs:eu-west-2:111122223333:other-router-failures"
    }
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ReadIncoming" && st.effect == "Allow" && toset(st.actions) == toset(["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging", "s3:GetObjectVersionTagging"]) && toset(st.resources) == toset(["arn:aws:s3:::other-incoming-111122223333/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ReadIncoming: Allow s3:GetObject, s3:GetObjectVersion, s3:GetObjectTagging and s3:GetObjectVersionTagging on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ListIncoming" && st.effect == "Allow" && toset(st.actions) == toset(["s3:ListBucket"]) && toset(st.resources) == toset(["arn:aws:s3:::other-incoming-111122223333"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ListIncoming: Allow s3:ListBucket on the incoming_bucket_arn variable itself (no /*). Without it S3 answers a missing object with 403 instead of 404."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "DeleteScannedVersion" && st.effect == "Allow" && toset(st.actions) == toset(["s3:DeleteObjectVersion"]) && toset(st.resources) == toset(["arn:aws:s3:::other-incoming-111122223333/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement DeleteScannedVersion: Allow s3:DeleteObjectVersion on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "WriteDestinations" && st.effect == "Allow" && toset(st.actions) == toset(["s3:PutObject", "s3:PutObjectTagging"]) && toset(st.resources) == toset(["arn:aws:s3:::other-approved-111122223333/*", "arn:aws:s3:::other-quarantine-111122223333/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement WriteDestinations: Allow s3:PutObject and s3:PutObjectTagging on the approved and quarantine bucket ARN variables, each followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "UpdateRow" && st.effect == "Allow" && toset(st.actions) == toset(["dynamodb:GetItem", "dynamodb:UpdateItem"]) && toset(st.resources) == toset(["arn:aws:dynamodb:us-east-1:111122223333:table/other-uploads"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement UpdateRow: Allow dynamodb:GetItem and dynamodb:UpdateItem on the table_arn variable."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.data_access.statement : st
      if st.sid == "ReportFailures" && st.effect == "Allow" && toset(st.actions) == toset(["sqs:SendMessage"]) && toset(st.resources) == toset(["arn:aws:sqs:eu-west-2:111122223333:other-router-failures"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.data_access needs statement ReportFailures: Allow sqs:SendMessage on the arn of aws_sqs_queue.failures."
  }

  assert {
    condition     = aws_iam_role_policy.router_data.name == "other-router-data"
    error_message = "The data policy's name must be built from the project_name variable, not fixed text."
  }
}
