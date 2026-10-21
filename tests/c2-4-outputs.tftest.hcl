# C2 step 4: the module's scan_rule_arn, dlq_arn and dlq_name outputs, and the root's scan_dlq_name.
# Brief: docs/milestones/C2.md

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

run "scan_outputs" {
  module {
    source = "./modules/scanning"
  }

  variables {
    project_name         = "demo"
    incoming_bucket_name = "demo-incoming-210987654321"
    incoming_bucket_arn  = "arn:aws:s3:::demo-incoming-210987654321"
    router_lambda_arn    = "arn:aws:lambda:us-east-1:210987654321:function:demo-router"
    alert_email          = "alerts@example.com"
  }

  # The mock gives every resource of a type the same values. Pin distinct ones
  # so a reference to the wrong resource or attribute fails.
  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      id  = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
    }
  }

  override_resource {
    target = aws_cloudwatch_event_rule.scan_result
    values = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"
    }
  }

  assert {
    condition     = output.scan_rule_arn == "arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"
    error_message = "scan_rule_arn must reference the arn of aws_cloudwatch_event_rule.scan_result (got ${output.scan_rule_arn})."
  }

  assert {
    condition     = output.dlq_arn == "arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"
    error_message = "dlq_arn must reference the arn of aws_sqs_queue.dlq (got ${output.dlq_arn})."
  }

  assert {
    condition     = output.dlq_name == "demo-scan-dlq"
    error_message = "dlq_name must reference the name of aws_sqs_queue.dlq (got ${output.dlq_name})."
  }
}

run "root_scan_dlq_name" {
  variables {
    project_name = "demo"
    owner        = "tester"
    alert_email  = "alerts@example.com"
  }

  assert {
    condition     = output.scan_dlq_name == "demo-scan-dlq"
    error_message = "The root outputs.tf needs an output scan_dlq_name = module.scanning.dlq_name (got ${try(output.scan_dlq_name, "nothing")})."
  }
}
