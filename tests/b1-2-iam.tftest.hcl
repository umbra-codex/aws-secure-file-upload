# B1 step 2: modules/upload_api/iam.tf, Lambda 1's role and permissions.
# Brief: docs/milestones/B1.md

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
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
}

run "upload_url_role" {
  module {
    source = "./modules/upload_api"
  }

  variables {
    project_name               = "demo"
    incoming_bucket_name       = "demo-incoming-210987654321"
    incoming_bucket_arn        = "arn:aws:s3:::demo-incoming-210987654321"
    table_name                 = "demo-uploads"
    table_arn                  = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    allowed_types              = ["image/png", "application/pdf"]
    max_size_mb                = 25
    router_function_name       = "demo-router"
    dlq_name                   = "demo-scan-dlq"
    router_failures_queue_name = "demo-router-failures"
  }

  # The mock gives every resource of a type the same values. Pin distinct ones
  # so a reference to the wrong resource or attribute fails.
  override_resource {
    target = aws_iam_role.upload_url
    values = {
      id  = "mock-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-upload-url"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.upload_url
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-upload-url"
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
    condition     = aws_iam_role.upload_url.name == "demo-upload-url"
    error_message = "aws_iam_role.upload_url must be named <project_name>-upload-url (got ${aws_iam_role.upload_url.name})."
  }

  assert {
    condition     = aws_iam_role.upload_url.assume_role_policy == data.aws_iam_policy_document.assume.json
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
    condition     = lookup(aws_iam_role.upload_url.tags, "Name", "") == "demo-upload-url" && lookup(aws_iam_role.upload_url.tags, "Role", "") == "upload-url" && lookup(aws_iam_role.upload_url.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_iam_role.upload_url needs tags Name = \"demo-upload-url\", Role = \"upload-url\", ManagedBy = \"terraform\" (got ${jsonencode(aws_iam_role.upload_url.tags)})."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "SignUploads" && st.effect == "Allow" && toset(st.actions) == toset(["s3:PutObject"]) && toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/uploads/*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement SignUploads: Allow s3:PutObject on the incoming_bucket_arn variable followed by /uploads/*, and nothing broader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "RecordUploads" && st.effect == "Allow" && toset(st.actions) == toset(["dynamodb:PutItem"]) && toset(st.resources) == toset(["arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement RecordUploads: Allow dynamodb:PutItem on the table_arn variable, and nothing broader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "WriteLogs" && st.effect == "Allow" && toset(st.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && toset(st.resources) == toset(["arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-upload-url:*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement WriteLogs: Allow logs:CreateLogStream and logs:PutLogEvents on the log group's arn followed by :*."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.permissions.statement) == 3
    error_message = "The permissions document must have exactly three statements (SignUploads, RecordUploads, WriteLogs). Least privilege: nothing else."
  }

  assert {
    condition     = aws_iam_role_policy.upload_url.name == "demo-upload-url" && aws_iam_role_policy.upload_url.role == aws_iam_role.upload_url.id && aws_iam_role_policy.upload_url.policy == data.aws_iam_policy_document.permissions.json
    error_message = "aws_iam_role_policy.upload_url must be named <project_name>-upload-url and reference the role's id and the permissions document's json."
  }
}
