# M0: the root module wires all five modules together and guards its inputs.
# Checked by CI on every push.

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

  # Later milestones add roles, functions, and log groups whose ARNs other
  # resources validate. The mock would invent random strings, so give every
  # resource of these types a well-formed ARN. (mock_resource needs no target,
  # so this is safe before those resources exist.)
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

  # C adds a rule, a queue, and a topic whose ARNs and URLs other resources
  # validate. Give every resource of these types a well-formed value.
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

variables {
  project_name = "demo"
  owner        = "tester"
  alert_email  = "alerts@example.com"
}

run "stack_wires_together" {
  assert {
    condition     = length(output.incoming_bucket_name) > 0 && length(output.approved_bucket_name) > 0 && length(output.quarantine_bucket_name) > 0
    error_message = "The root module must expose incoming_bucket_name, approved_bucket_name, and quarantine_bucket_name."
  }

  assert {
    condition     = length(output.api_url) > 0 && length(output.table_name) > 0
    error_message = "The root module must expose api_url and table_name."
  }

  assert {
    condition     = var.region == "us-east-1"
    error_message = "region must default to us-east-1."
  }
}

run "rejects_bad_project_name" {
  command = plan

  variables {
    project_name = "Bad_Name"
  }

  expect_failures = [var.project_name]
}

run "rejects_oversize_limit" {
  command = plan

  variables {
    max_size_mb = 500
  }

  expect_failures = [var.max_size_mb]
}

run "rejects_bad_email" {
  command = plan

  variables {
    alert_email = "not-an-email"
  }

  expect_failures = [var.alert_email]
}

run "rejects_bad_region" {
  command = plan

  variables {
    region = "us-east-1a"
  }

  expect_failures = [var.region]
}
