# B2 step 2: modules/upload_api/api.tf, the access log group, the HTTP API, and its stage.
# Brief: docs/milestones/B2.md

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

run "http_api" {
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
    target = aws_cloudwatch_log_group.upload_url
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-upload-url"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.api_access
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/apigateway/demo-api"
    }
  }

  override_resource {
    target = aws_apigatewayv2_api.this
    values = {
      id            = "demo-api-id"
      arn           = "arn:aws:apigateway:us-east-1::/apis/demo-api-id"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:demo-api-id"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.api_access.name == "/aws/apigateway/demo-api" && aws_cloudwatch_log_group.api_access.retention_in_days == 14
    error_message = "aws_cloudwatch_log_group.api_access must be named /aws/apigateway/<project_name>-api with retention_in_days = 14 (got ${aws_cloudwatch_log_group.api_access.name}, ${aws_cloudwatch_log_group.api_access.retention_in_days})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_log_group.api_access.tags, "Name", "") == "/aws/apigateway/demo-api" && lookup(aws_cloudwatch_log_group.api_access.tags, "Role", "") == "api" && lookup(aws_cloudwatch_log_group.api_access.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_log_group.api_access needs tags Name = \"/aws/apigateway/demo-api\", Role = \"api\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_log_group.api_access.tags)})."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.name == "demo-api" && aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "aws_apigatewayv2_api.this must be named <project_name>-api with protocol_type \"HTTP\" (got ${aws_apigatewayv2_api.this.name}, ${aws_apigatewayv2_api.this.protocol_type})."
  }

  assert {
    condition     = lookup(aws_apigatewayv2_api.this.tags, "Name", "") == "demo-api" && lookup(aws_apigatewayv2_api.this.tags, "Role", "") == "api" && lookup(aws_apigatewayv2_api.this.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_apigatewayv2_api.this needs tags Name = \"demo-api\", Role = \"api\", ManagedBy = \"terraform\" (got ${jsonencode(aws_apigatewayv2_api.this.tags)})."
  }

  assert {
    condition     = aws_apigatewayv2_stage.default.api_id == "demo-api-id" && aws_apigatewayv2_stage.default.name == "$default" && aws_apigatewayv2_stage.default.auto_deploy == true
    error_message = "aws_apigatewayv2_stage.default must use the API's id, be named \"$default\", and set auto_deploy = true (got name ${aws_apigatewayv2_stage.default.name})."
  }

  assert {
    condition = length(aws_apigatewayv2_stage.default.access_log_settings) == 1 && alltrue([
      for s in aws_apigatewayv2_stage.default.access_log_settings :
      s.destination_arn == "arn:aws:logs:us-east-1:210987654321:log-group:/aws/apigateway/demo-api"
    ])
    error_message = "The stage needs one access_log_settings block whose destination_arn is the arn of aws_cloudwatch_log_group.api_access (not Lambda 1's log group)."
  }

  assert {
    condition = length(aws_apigatewayv2_stage.default.access_log_settings) == 1 && alltrue([
      for s in aws_apigatewayv2_stage.default.access_log_settings :
      can(jsondecode(s.format)) && alltrue([
        for v in ["$context.requestId", "$context.identity.sourceIp", "$context.requestTime", "$context.routeKey", "$context.status", "$context.responseLength", "$context.integrationErrorMessage"] :
        contains(values(jsondecode(s.format)), v)
      ])
    ])
    error_message = "The access log format must be JSON (built with jsonencode) and include all seven values from the brief: $context.requestId, $context.identity.sourceIp, $context.requestTime, $context.routeKey, $context.status, $context.responseLength, and $context.integrationErrorMessage."
  }

  assert {
    condition     = lookup(aws_apigatewayv2_stage.default.tags, "Name", "") == "demo-api-default" && lookup(aws_apigatewayv2_stage.default.tags, "Role", "") == "api" && lookup(aws_apigatewayv2_stage.default.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_apigatewayv2_stage.default needs tags Name = \"demo-api-default\", Role = \"api\", ManagedBy = \"terraform\" (got ${jsonencode(aws_apigatewayv2_stage.default.tags)})."
  }
}
