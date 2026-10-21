# B1 step 4: modules/upload_api/outputs.tf and the root outputs.tf
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

run "upload_url_outputs" {
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

  assert {
    condition     = output.upload_role_arn == "arn:aws:iam::210987654321:role/demo-upload-url"
    error_message = "upload_role_arn must reference the role's arn (still the placeholder? got ${output.upload_role_arn})."
  }

  assert {
    condition     = output.upload_function_name == aws_lambda_function.upload_url.function_name
    error_message = "upload_function_name must reference the function's function_name."
  }
}

# The root module (repo root) passes the function name up, so "Done when" can
# use terraform output.
run "root_upload_function_name" {
  variables {
    project_name = "demo"
    owner        = "tester"
    alert_email  = "alerts@example.com"
  }

  assert {
    condition     = output.upload_function_name == "demo-upload-url"
    error_message = "The root outputs.tf needs an output upload_function_name = module.upload_api.upload_function_name (got ${try(output.upload_function_name, "nothing")})."
  }
}
