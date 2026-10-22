# D4 step 2: modules/processing/lambda.tf, memory sized from measurements.
# Brief: docs/milestones/D4.md
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

run "memory_right_sized" {
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

  assert {
    condition     = contains([128, 192, 256, 384], aws_lambda_function.router.memory_size)
    error_message = "memory_size must be one of 128, 192, 256 or 384, chosen from the Max Memory Used in your REPORT lines (got ${aws_lambda_function.router.memory_size}). D1's starting value of 512 is more than this function needs."
  }

  assert {
    condition     = aws_lambda_function.router.timeout == 30
    error_message = "timeout must stay 30 seconds (got ${aws_lambda_function.router.timeout})."
  }
}
