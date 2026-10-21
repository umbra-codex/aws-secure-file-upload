# B2 step 3: modules/upload_api/api.tf, the POST /upload-url route to Lambda 1.
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

run "upload_url_route" {
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
    target = aws_lambda_function.upload_url
    values = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:demo-upload-url"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:demo-upload-url/invocations"
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

  override_resource {
    target = aws_apigatewayv2_integration.upload_url
    values = {
      id = "mock-integration-id"
    }
  }

  assert {
    condition = (
      aws_apigatewayv2_integration.upload_url.api_id == "demo-api-id" &&
      aws_apigatewayv2_integration.upload_url.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.upload_url.payload_format_version == "2.0"
    )
    error_message = "aws_apigatewayv2_integration.upload_url must use the API's id, integration_type \"AWS_PROXY\", and payload_format_version \"2.0\"."
  }

  assert {
    condition     = aws_apigatewayv2_integration.upload_url.integration_uri == aws_lambda_function.upload_url.invoke_arn
    error_message = "The integration's integration_uri must reference the function's invoke_arn (not its arn)."
  }

  assert {
    condition     = aws_apigatewayv2_route.upload_url.api_id == "demo-api-id" && aws_apigatewayv2_route.upload_url.route_key == "POST /upload-url"
    error_message = "aws_apigatewayv2_route.upload_url must use the API's id and route_key \"POST /upload-url\" (got ${aws_apigatewayv2_route.upload_url.route_key})."
  }

  assert {
    condition     = aws_apigatewayv2_route.upload_url.target == "integrations/mock-integration-id"
    error_message = "The route's target must be \"integrations/\" followed by the integration's id (got ${aws_apigatewayv2_route.upload_url.target})."
  }

  assert {
    condition = (
      aws_lambda_permission.api.statement_id == "AllowApiGatewayInvoke" &&
      aws_lambda_permission.api.action == "lambda:InvokeFunction" &&
      aws_lambda_permission.api.principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.api.function_name == aws_lambda_function.upload_url.function_name &&
      aws_lambda_permission.api.source_arn == "arn:aws:execute-api:us-east-1:210987654321:demo-api-id/*/*"
    )
    error_message = "aws_lambda_permission.api must let apigateway.amazonaws.com call lambda:InvokeFunction on Lambda 1, with source_arn = the API's execution_arn followed by /*/* (got ${aws_lambda_permission.api.source_arn})."
  }
}
