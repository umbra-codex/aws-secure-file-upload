# C2 step 2: modules/scanning/dlq.tf, the target DLQ and its queue policy.
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

run "scan_dlq" {
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

  # The mock gives every policy document the same JSON, so a reference to the
  # wrong document would pass. Pin a distinct JSON for each one.
  override_data {
    target = data.aws_iam_policy_document.assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockAssume\"}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.permissions
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockPermissions\"}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.dlq
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockDlq\"}]}"
    }
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "demo-scan-dlq"
    error_message = "aws_sqs_queue.dlq must be named <project_name>-scan-dlq (got ${aws_sqs_queue.dlq.name})."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600 && aws_sqs_queue.dlq.sqs_managed_sse_enabled == true
    error_message = "aws_sqs_queue.dlq needs message_retention_seconds = 1209600 (14 days) and sqs_managed_sse_enabled = true (got ${aws_sqs_queue.dlq.message_retention_seconds}, ${aws_sqs_queue.dlq.sqs_managed_sse_enabled})."
  }

  assert {
    condition     = lookup(aws_sqs_queue.dlq.tags, "Name", "") == "demo-scan-dlq" && lookup(aws_sqs_queue.dlq.tags, "Role", "") == "scan-dlq" && lookup(aws_sqs_queue.dlq.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_sqs_queue.dlq needs tags Name = \"demo-scan-dlq\", Role = \"scan-dlq\", ManagedBy = \"terraform\" (got ${jsonencode(aws_sqs_queue.dlq.tags)})."
  }

  assert {
    condition = length(data.aws_iam_policy_document.dlq.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.dlq.statement :
      st.sid == "AllowScanRuleToSendFailedEvents" && st.effect == "Allow" && toset(st.actions) == toset(["sqs:SendMessage"]) &&
      toset(st.resources) == toset(["arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["events.amazonaws.com"])]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "ArnEquals" && c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"])])
    ])
    error_message = "data.aws_iam_policy_document.dlq needs one statement, sid AllowScanRuleToSendFailedEvents: Allow sqs:SendMessage on the queue's arn for principal type \"Service\", identifiers [\"events.amazonaws.com\"], with condition ArnEquals aws:SourceArn = the scan-result rule's arn."
  }

  assert {
    condition     = aws_sqs_queue_policy.dlq.queue_url == "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq" && aws_sqs_queue_policy.dlq.policy == data.aws_iam_policy_document.dlq.json
    error_message = "aws_sqs_queue_policy.dlq must set queue_url to the queue's url and policy to the json of data.aws_iam_policy_document.dlq."
  }
}
