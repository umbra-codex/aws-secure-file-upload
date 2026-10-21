# B3 step 2: modules/upload_api/api.tf, API throttling and CORS.
# Brief: docs/milestones/B3.md

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

run "api_limits" {
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
    cors_allowed_origins       = ["http://localhost:3000", "https://app.example.com"]
  }

  assert {
    condition = length(aws_apigatewayv2_stage.default.default_route_settings) == 1 && alltrue([
      for r in aws_apigatewayv2_stage.default.default_route_settings :
      r.throttling_burst_limit == 10 && r.throttling_rate_limit == 5
    ])
    error_message = "The stage needs one default_route_settings block with throttling_burst_limit = 10 and throttling_rate_limit = 5."
  }

  assert {
    condition = length(aws_apigatewayv2_api.this.cors_configuration) == 1 && alltrue([
      for c in aws_apigatewayv2_api.this.cors_configuration :
      toset(c.allow_origins) == toset(["http://localhost:3000", "https://app.example.com"]) &&
      toset(c.allow_methods) == toset(["GET", "POST"]) &&
      toset([for h in c.allow_headers : lower(h)]) == toset(["content-type"]) &&
      c.max_age == 300
    ])
    error_message = "The API needs one cors_configuration block: allow_origins = the cors_allowed_origins variable, allow_methods [\"GET\", \"POST\"], allow_headers [\"content-type\"], max_age 300."
  }
}

# With no origins, the default, the API still gets a CORS block that allows none.
run "api_cors_default" {
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

  assert {
    condition     = length(aws_apigatewayv2_api.this.cors_configuration) == 1 && alltrue([for c in aws_apigatewayv2_api.this.cors_configuration : length(c.allow_origins) == 0])
    error_message = "With cors_allowed_origins at its default, the API must still have one cors_configuration block, with no origins. The variable must default to an empty list ([])."
  }
}
