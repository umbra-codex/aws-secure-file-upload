# B1 step 3: modules/upload_api/lambda.tf, the log group, the zip, and the function.
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

run "upload_url_function" {
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

  override_resource {
    target = aws_lambda_function.upload_url
    values = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:demo-upload-url"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:demo-upload-url/invocations"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.upload_url.name == "/aws/lambda/demo-upload-url" && aws_cloudwatch_log_group.upload_url.retention_in_days == 14
    error_message = "aws_cloudwatch_log_group.upload_url must be named /aws/lambda/<project_name>-upload-url with retention_in_days = 14 (got ${aws_cloudwatch_log_group.upload_url.name}, ${aws_cloudwatch_log_group.upload_url.retention_in_days})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_log_group.upload_url.tags, "Name", "") == "/aws/lambda/demo-upload-url" && lookup(aws_cloudwatch_log_group.upload_url.tags, "Role", "") == "upload-url" && lookup(aws_cloudwatch_log_group.upload_url.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_log_group.upload_url needs tags Name = \"/aws/lambda/demo-upload-url\", Role = \"upload-url\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_log_group.upload_url.tags)})."
  }

  assert {
    condition     = data.archive_file.upload_url.type == "zip" && endswith(data.archive_file.upload_url.source_dir, "/src") && endswith(data.archive_file.upload_url.output_path, "/build/upload_url.zip")
    error_message = "data.archive_file.upload_url must zip the module's src folder (source_dir = path.module followed by /src) into build/upload_url.zip."
  }

  assert {
    condition = (
      aws_lambda_function.upload_url.function_name == "demo-upload-url" &&
      aws_lambda_function.upload_url.runtime == "python3.13" &&
      aws_lambda_function.upload_url.handler == "handler.handler" &&
      toset(aws_lambda_function.upload_url.architectures) == toset(["arm64"]) &&
      aws_lambda_function.upload_url.timeout == 10 &&
      aws_lambda_function.upload_url.memory_size == 128
    )
    error_message = "aws_lambda_function.upload_url must be named <project_name>-upload-url, with runtime python3.13, handler handler.handler, architectures [\"arm64\"], timeout 10, memory_size 128."
  }

  assert {
    condition     = aws_lambda_function.upload_url.role == "arn:aws:iam::210987654321:role/demo-upload-url"
    error_message = "The function's role must reference the role's arn (got ${aws_lambda_function.upload_url.role})."
  }

  assert {
    condition     = aws_lambda_function.upload_url.filename == data.archive_file.upload_url.output_path && aws_lambda_function.upload_url.source_code_hash == data.archive_file.upload_url.output_base64sha256
    error_message = "The function's filename and source_code_hash must reference the archive's output_path and output_base64sha256, so code changes redeploy."
  }

  assert {
    condition = length(aws_lambda_function.upload_url.environment) == 1 && one(aws_lambda_function.upload_url.environment).variables == tomap({
      TABLE_NAME    = "demo-uploads"
      BUCKET_NAME   = "demo-incoming-210987654321"
      ALLOWED_TYPES = "image/png,application/pdf"
      MAX_SIZE_MB   = "25"
    })
    error_message = "The environment block's variables must be exactly TABLE_NAME = the table_name variable, BUCKET_NAME = the incoming_bucket_name variable, ALLOWED_TYPES = the allowed_types variable joined with commas, MAX_SIZE_MB = the max_size_mb variable (got ${jsonencode(try(one(aws_lambda_function.upload_url.environment).variables, {}))})."
  }

  assert {
    condition = length(aws_lambda_function.upload_url.logging_config) == 1 && alltrue([
      for lc in aws_lambda_function.upload_url.logging_config :
      lc.log_format == "JSON" && lc.application_log_level == "INFO" && lc.log_group == "/aws/lambda/demo-upload-url"
    ])
    error_message = "The function needs one logging_config block: log_format \"JSON\", application_log_level \"INFO\", log_group = the log group's name."
  }

  assert {
    condition     = lookup(aws_lambda_function.upload_url.tags, "Name", "") == "demo-upload-url" && lookup(aws_lambda_function.upload_url.tags, "Role", "") == "upload-url" && lookup(aws_lambda_function.upload_url.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_lambda_function.upload_url needs tags Name = \"demo-upload-url\", Role = \"upload-url\", ManagedBy = \"terraform\" (got ${jsonencode(aws_lambda_function.upload_url.tags)})."
  }
}
