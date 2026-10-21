# D1 step 3: modules/processing/lambda.tf, the log group, the zip, and Lambda 2.
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

run "router_function" {
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

  override_resource {
    target = aws_lambda_function.router
    values = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:demo-router"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:demo-router/invocations"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.router.name == "/aws/lambda/demo-router" && aws_cloudwatch_log_group.router.retention_in_days == 14
    error_message = "aws_cloudwatch_log_group.router must be named /aws/lambda/<project_name>-router with retention_in_days = 14 (got ${aws_cloudwatch_log_group.router.name}, ${aws_cloudwatch_log_group.router.retention_in_days})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_log_group.router.tags, "Name", "") == "/aws/lambda/demo-router" && lookup(aws_cloudwatch_log_group.router.tags, "Role", "") == "router" && lookup(aws_cloudwatch_log_group.router.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_log_group.router needs tags Name = \"/aws/lambda/demo-router\", Role = \"router\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_log_group.router.tags)})."
  }

  assert {
    condition     = data.archive_file.router.type == "zip" && endswith(data.archive_file.router.source_dir, "/src") && endswith(data.archive_file.router.output_path, "/build/router.zip")
    error_message = "data.archive_file.router must zip the module's src folder (source_dir = path.module followed by /src) into build/router.zip."
  }

  assert {
    condition = (
      aws_lambda_function.router.function_name == "demo-router" &&
      aws_lambda_function.router.runtime == "python3.13" &&
      aws_lambda_function.router.handler == "handler.handler" &&
      toset(aws_lambda_function.router.architectures) == toset(["arm64"]) &&
      aws_lambda_function.router.timeout == 30
    )
    error_message = "aws_lambda_function.router must be named <project_name>-router, with runtime python3.13, handler handler.handler, architectures [\"arm64\"], timeout 30."
  }

  assert {
    condition     = aws_lambda_function.router.memory_size >= 128 && aws_lambda_function.router.memory_size <= 512
    error_message = "memory_size must be between 128 and 512 (the brief starts it at 512; D4 lowers it from measurements). Got ${aws_lambda_function.router.memory_size}."
  }

  assert {
    condition     = aws_lambda_function.router.role == "arn:aws:iam::210987654321:role/demo-router"
    error_message = "The function's role must reference the role's arn (got ${aws_lambda_function.router.role})."
  }

  assert {
    condition     = aws_lambda_function.router.filename == data.archive_file.router.output_path && aws_lambda_function.router.source_code_hash == data.archive_file.router.output_base64sha256
    error_message = "The function's filename and source_code_hash must reference the archive's output_path and output_base64sha256, so code changes redeploy."
  }

  assert {
    condition = length(aws_lambda_function.router.environment) == 1 && one(aws_lambda_function.router.environment).variables == tomap({
      TABLE_NAME        = "demo-uploads"
      INCOMING_BUCKET   = "demo-incoming-210987654321"
      APPROVED_BUCKET   = "demo-approved-210987654321"
      QUARANTINE_BUCKET = "demo-quarantine-210987654321"
      ALLOWED_TYPES     = "image/png,application/pdf"
      MAX_SIZE_MB       = "25"
    })
    error_message = "The environment block's variables must be exactly TABLE_NAME, INCOMING_BUCKET, APPROVED_BUCKET, QUARANTINE_BUCKET (the matching name variables), ALLOWED_TYPES (the allowed_types variable joined with commas) and MAX_SIZE_MB (the max_size_mb variable). Got ${jsonencode(try(one(aws_lambda_function.router.environment).variables, {}))}."
  }

  assert {
    condition = length(aws_lambda_function.router.logging_config) == 1 && alltrue([
      for lc in aws_lambda_function.router.logging_config :
      lc.log_format == "JSON" && lc.application_log_level == "INFO" && lc.log_group == "/aws/lambda/demo-router"
    ])
    error_message = "The function needs one logging_config block: log_format \"JSON\", application_log_level \"INFO\", log_group = the log group's name."
  }

  assert {
    condition     = lookup(aws_lambda_function.router.tags, "Name", "") == "demo-router" && lookup(aws_lambda_function.router.tags, "Role", "") == "router" && lookup(aws_lambda_function.router.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_lambda_function.router needs tags Name = \"demo-router\", Role = \"router\", ManagedBy = \"terraform\" (got ${jsonencode(aws_lambda_function.router.tags)})."
  }
}

# Nothing may be fixed text: give every input another value and the function must follow.
run "function_follows_its_inputs" {
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

  assert {
    condition     = aws_lambda_function.router.function_name == "other-router" && aws_cloudwatch_log_group.router.name == "/aws/lambda/other-router"
    error_message = "The function and the log group must build their names from the project_name variable, not fixed text."
  }

  assert {
    condition = length(aws_lambda_function.router.environment) == 1 && one(aws_lambda_function.router.environment).variables == tomap({
      TABLE_NAME        = "other-uploads"
      INCOMING_BUCKET   = "other-incoming-111122223333"
      APPROVED_BUCKET   = "other-approved-111122223333"
      QUARANTINE_BUCKET = "other-quarantine-111122223333"
      ALLOWED_TYPES     = "image/jpeg"
      MAX_SIZE_MB       = "5"
    })
    error_message = "Every environment variable must come from its module variable, not fixed text (got ${jsonencode(try(one(aws_lambda_function.router.environment).variables, {}))})."
  }

  assert {
    condition     = length(aws_lambda_function.router.logging_config) == 1 && alltrue([for lc in aws_lambda_function.router.logging_config : lc.log_group == "/aws/lambda/other-router"])
    error_message = "logging_config's log_group must be the log group's name attribute, not fixed text."
  }
}
