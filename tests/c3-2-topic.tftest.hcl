# C3 step 2: modules/scanning/alerts_topic.tf, the topic, its policy, and the email subscription.
# Brief: docs/milestones/C3.md

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

run "alerts_topic" {
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
    target = aws_cloudwatch_event_rule.scan_result
    values = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"
    }
  }

  override_resource {
    target = aws_cloudwatch_event_rule.alerts
    values = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/demo-alerts"
    }
  }

  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      id  = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
    }
  }

  override_resource {
    target = aws_sns_topic.alerts
    values = {
      arn = "arn:aws:sns:us-east-1:210987654321:demo-alerts"
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

  override_data {
    target = data.aws_iam_policy_document.alerts_topic
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockAlertsTopic\"}]}"
    }
  }

  assert {
    condition     = aws_sns_topic.alerts.name == "demo-alerts"
    error_message = "aws_sns_topic.alerts must be named <project_name>-alerts (got ${aws_sns_topic.alerts.name})."
  }

  assert {
    condition     = lookup(aws_sns_topic.alerts.tags, "Name", "") == "demo-alerts" && lookup(aws_sns_topic.alerts.tags, "Role", "") == "alerts" && lookup(aws_sns_topic.alerts.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_sns_topic.alerts needs tags Name = \"demo-alerts\", Role = \"alerts\", ManagedBy = \"terraform\" (got ${jsonencode(aws_sns_topic.alerts.tags)})."
  }

  assert {
    condition = length(data.aws_iam_policy_document.alerts_topic.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.alerts_topic.statement :
      st.sid == "AllowAlertRuleToPublish" && st.effect == "Allow" && toset(st.actions) == toset(["sns:Publish"]) &&
      toset(st.resources) == toset(["arn:aws:sns:us-east-1:210987654321:demo-alerts"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["events.amazonaws.com"])]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "ArnEquals" && c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:events:us-east-1:210987654321:rule/demo-alerts"])])
    ])
    error_message = "data.aws_iam_policy_document.alerts_topic needs one statement, sid AllowAlertRuleToPublish: Allow sns:Publish on the topic's arn for principal type \"Service\", identifiers [\"events.amazonaws.com\"], with condition ArnEquals aws:SourceArn = the alert rule's arn (not the scan-result rule's)."
  }

  assert {
    condition     = aws_sns_topic_policy.alerts.arn == "arn:aws:sns:us-east-1:210987654321:demo-alerts" && aws_sns_topic_policy.alerts.policy == data.aws_iam_policy_document.alerts_topic.json
    error_message = "aws_sns_topic_policy.alerts must set arn to the topic's arn and policy to the json of data.aws_iam_policy_document.alerts_topic."
  }

  assert {
    condition     = aws_sns_topic_subscription.email.topic_arn == "arn:aws:sns:us-east-1:210987654321:demo-alerts" && aws_sns_topic_subscription.email.protocol == "email" && aws_sns_topic_subscription.email.endpoint == "alerts@example.com"
    error_message = "aws_sns_topic_subscription.email needs topic_arn = the topic's arn, protocol = \"email\", and endpoint = the alert_email variable (got ${aws_sns_topic_subscription.email.protocol}, ${aws_sns_topic_subscription.email.endpoint})."
  }
}
