# D1 step 2: modules/processing/iam.tf, Lambda 2's role and its logging permission.
# Brief: docs/milestones/D1.md
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

run "router_role" {
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
    target = aws_cloudwatch_log_group.router
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-router"
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

  assert {
    condition     = aws_iam_role.router.name == "demo-router"
    error_message = "aws_iam_role.router must be named <project_name>-router (got ${aws_iam_role.router.name})."
  }

  assert {
    condition     = aws_iam_role.router.assume_role_policy == data.aws_iam_policy_document.assume.json
    error_message = "The role's assume_role_policy must reference the json of data.aws_iam_policy_document.assume."
  }

  assert {
    condition = length(data.aws_iam_policy_document.assume.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.assume.statement :
      st.effect == "Allow" && toset(st.actions) == toset(["sts:AssumeRole"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["lambda.amazonaws.com"])])
    ])
    error_message = "data.aws_iam_policy_document.assume needs one statement: Allow sts:AssumeRole for principal type \"Service\", identifiers [\"lambda.amazonaws.com\"]."
  }

  assert {
    condition     = lookup(aws_iam_role.router.tags, "Name", "") == "demo-router" && lookup(aws_iam_role.router.tags, "Role", "") == "router" && lookup(aws_iam_role.router.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_iam_role.router needs tags Name = \"demo-router\", Role = \"router\", ManagedBy = \"terraform\" (got ${jsonencode(aws_iam_role.router.tags)})."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "WriteLogs" && st.effect == "Allow" && toset(st.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && toset(st.resources) == toset(["arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-router:*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement WriteLogs: Allow logs:CreateLogStream and logs:PutLogEvents on the log group's arn followed by :*."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.permissions.statement) == 1
    error_message = "The permissions document must have exactly one statement (WriteLogs). D2 adds the data permissions in a separate document."
  }

  assert {
    condition     = aws_iam_role_policy.router.name == "demo-router" && aws_iam_role_policy.router.role == aws_iam_role.router.id && aws_iam_role_policy.router.policy == data.aws_iam_policy_document.permissions.json
    error_message = "aws_iam_role_policy.router must be named <project_name>-router and reference the role's id and the permissions document's json."
  }
}

# Nothing may be fixed text: give the project another name and every name must follow.
run "names_follow_project_name" {
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
    target = aws_cloudwatch_log_group.router
    values = {
      arn = "arn:aws:logs:us-east-1:111122223333:log-group:/aws/lambda/other-router"
    }
  }

  assert {
    condition     = aws_iam_role.router.name == "other-router" && lookup(aws_iam_role.router.tags, "Name", "") == "other-router"
    error_message = "The role's name and its Name tag must be built from the project_name variable, not fixed text."
  }

  assert {
    condition     = aws_iam_role_policy.router.name == "other-router"
    error_message = "The role policy's name must be built from the project_name variable, not fixed text."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "WriteLogs" && toset(st.resources) == toset(["arn:aws:logs:us-east-1:111122223333:log-group:/aws/lambda/other-router:*"])
    ]) == 1
    error_message = "WriteLogs must build its resource from the log group's arn attribute, not from fixed text."
  }
}
