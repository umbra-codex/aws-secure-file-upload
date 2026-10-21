# C1 step 4: the module's guardduty_role_arn and guardduty_plan_id outputs, and the root's guardduty_plan_id.
# Brief: docs/milestones/C1.md

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

run "guardduty_outputs" {
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
    target = aws_iam_role.guardduty
    values = {
      id  = "mock-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-guardduty"
    }
  }

  override_resource {
    target = aws_guardduty_malware_protection_plan.incoming
    values = {
      id  = "mock-plan-id-0001"
      arn = "arn:aws:guardduty:us-east-1:210987654321:malware-protection-plan/mock-plan-id-0001"
    }
  }

  assert {
    condition     = output.guardduty_role_arn == "arn:aws:iam::210987654321:role/demo-guardduty"
    error_message = "guardduty_role_arn must reference the arn of aws_iam_role.guardduty (got ${output.guardduty_role_arn})."
  }

  assert {
    condition     = output.guardduty_plan_id == "mock-plan-id-0001"
    error_message = "guardduty_plan_id must reference the id of aws_guardduty_malware_protection_plan.incoming (got ${try(output.guardduty_plan_id, "nothing")})."
  }
}

run "root_guardduty_plan_id" {
  variables {
    project_name = "demo"
    owner        = "tester"
    alert_email  = "alerts@example.com"
  }

  assert {
    condition     = output.guardduty_plan_id == module.scanning.guardduty_plan_id && output.guardduty_plan_id != module.scanning.guardduty_role_arn
    error_message = "The root outputs.tf needs an output guardduty_plan_id = module.scanning.guardduty_plan_id (got ${try(output.guardduty_plan_id, "nothing")})."
  }
}
