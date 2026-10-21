# C1 step 2: modules/scanning/guardduty.tf, the malware protection plan.
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

run "protection_plan" {
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

  assert {
    condition     = aws_guardduty_malware_protection_plan.incoming.role == "arn:aws:iam::210987654321:role/demo-guardduty"
    error_message = "aws_guardduty_malware_protection_plan.incoming must set role to the arn of aws_iam_role.guardduty (got ${aws_guardduty_malware_protection_plan.incoming.role})."
  }

  assert {
    condition = (
      length(aws_guardduty_malware_protection_plan.incoming.protected_resource) == 1 &&
      length(aws_guardduty_malware_protection_plan.incoming.protected_resource[0].s3_bucket) == 1 &&
      aws_guardduty_malware_protection_plan.incoming.protected_resource[0].s3_bucket[0].bucket_name == "demo-incoming-210987654321"
    )
    error_message = "The plan needs one protected_resource block holding one s3_bucket block whose bucket_name is the incoming_bucket_name variable."
  }

  assert {
    condition     = length(aws_guardduty_malware_protection_plan.incoming.protected_resource) == 1 && length(aws_guardduty_malware_protection_plan.incoming.protected_resource[0].s3_bucket) == 1 && toset(aws_guardduty_malware_protection_plan.incoming.protected_resource[0].s3_bucket[0].object_prefixes) == toset(["uploads/"])
    error_message = "The s3_bucket block must set object_prefixes to exactly [\"uploads/\"], so only uploads are scanned (got ${jsonencode(try(aws_guardduty_malware_protection_plan.incoming.protected_resource[0].s3_bucket[0].object_prefixes, "nothing"))})."
  }

  assert {
    condition = (
      length(aws_guardduty_malware_protection_plan.incoming.actions) == 1 &&
      length(aws_guardduty_malware_protection_plan.incoming.actions[0].tagging) == 1 &&
      aws_guardduty_malware_protection_plan.incoming.actions[0].tagging[0].status == "ENABLED"
    )
    error_message = "The plan needs an actions block holding one tagging block with status = \"ENABLED\" (got ${jsonencode(aws_guardduty_malware_protection_plan.incoming.actions)})."
  }

  assert {
    condition     = lookup(aws_guardduty_malware_protection_plan.incoming.tags, "Name", "") == "demo-incoming-scan" && lookup(aws_guardduty_malware_protection_plan.incoming.tags, "Role", "") == "guardduty" && lookup(aws_guardduty_malware_protection_plan.incoming.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_guardduty_malware_protection_plan.incoming needs tags Name = \"demo-incoming-scan\", Role = \"guardduty\", ManagedBy = \"terraform\" (got ${jsonencode(aws_guardduty_malware_protection_plan.incoming.tags)})."
  }
}
