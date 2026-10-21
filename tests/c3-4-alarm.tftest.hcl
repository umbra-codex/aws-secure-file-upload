# C3 step 4: modules/scanning/alarm.tf, the DLQ alarm.
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

run "dlq_alarm" {
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
    target = aws_sns_topic.alerts
    values = {
      arn = "arn:aws:sns:us-east-1:210987654321:demo-alerts"
    }
  }

  override_resource {
    target = aws_cloudwatch_metric_alarm.dlq_not_empty
    values = {
      arn = "arn:aws:cloudwatch:us-east-1:210987654321:alarm:demo-scan-dlq-not-empty"
    }
  }

  assert {
    condition = (
      length(trimspace(try(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_description, ""))) > 0 &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_name == "demo-scan-dlq-not-empty" &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.namespace == "AWS/SQS" &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.metric_name == "ApproximateNumberOfMessagesVisible" &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.dimensions == tomap({ QueueName = "demo-scan-dlq" }) &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.statistic == "Maximum" &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.period == 60 &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.threshold == 0 &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.dlq_not_empty.treat_missing_data == "notBreaching"
    )
    error_message = "aws_cloudwatch_metric_alarm.dlq_not_empty must be named demo-scan-dlq-not-empty and watch AWS/SQS ApproximateNumberOfMessagesVisible for QueueName demo-scan-dlq: Maximum over 60 seconds, 1 evaluation period, GreaterThanThreshold 0, treat_missing_data notBreaching, and an alarm_description (got ${jsonencode(aws_cloudwatch_metric_alarm.dlq_not_empty.dimensions)})."
  }

  assert {
    condition = (
      try(toset(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_actions), toset([])) == toset(["arn:aws:sns:us-east-1:210987654321:demo-alerts"]) &&
      try(length(aws_cloudwatch_metric_alarm.dlq_not_empty.ok_actions), 0) == 0 &&
      try(length(aws_cloudwatch_metric_alarm.dlq_not_empty.insufficient_data_actions), 0) == 0
    )
    error_message = "aws_cloudwatch_metric_alarm.dlq_not_empty needs alarm_actions = a list holding the arn of aws_sns_topic.alerts, and no ok_actions or insufficient_data_actions: only the move into ALARM sends mail (got ${jsonencode(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_actions)})."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.alerts_topic.statement : st
      if st.sid == "AllowDlqAlarmToPublish" && st.effect == "Allow" && toset(st.actions) == toset(["sns:Publish"]) &&
      toset(st.resources) == toset(["arn:aws:sns:us-east-1:210987654321:demo-alerts"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudwatch.amazonaws.com"])]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "ArnEquals" && c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:cloudwatch:us-east-1:210987654321:alarm:demo-scan-dlq-not-empty"])])
    ]) == 1 && length(data.aws_iam_policy_document.alerts_topic.statement) == 2
    error_message = "data.aws_iam_policy_document.alerts_topic needs a second statement, sid AllowDlqAlarmToPublish: Allow sns:Publish on the topic's arn for principal type \"Service\", identifiers [\"cloudwatch.amazonaws.com\"], with condition ArnEquals aws:SourceArn = the DLQ alarm's arn, and the document must hold exactly two statements (the alert rule's and the alarm's)."
  }

  assert {
    condition     = lookup(aws_cloudwatch_metric_alarm.dlq_not_empty.tags, "Name", "") == "demo-scan-dlq-not-empty" && lookup(aws_cloudwatch_metric_alarm.dlq_not_empty.tags, "Role", "") == "observability" && lookup(aws_cloudwatch_metric_alarm.dlq_not_empty.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_metric_alarm.dlq_not_empty needs tags Name = \"demo-scan-dlq-not-empty\", Role = \"observability\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_metric_alarm.dlq_not_empty.tags)})."
  }
}

# The alarm action and the alarm's policy statement must follow the topic and
# the alarm, not text that happens to equal the values above.
run "alarm_wiring_follows_its_inputs" {
  module {
    source = "./modules/scanning"
  }

  variables {
    project_name         = "other"
    incoming_bucket_name = "other-incoming-111122223333"
    incoming_bucket_arn  = "arn:aws:s3:::other-incoming-111122223333"
    router_lambda_arn    = "arn:aws:lambda:eu-west-2:111122223333:function:other-router"
    alert_email          = "alerts@example.com"
  }

  override_resource {
    target = aws_sns_topic.alerts
    values = {
      arn = "arn:aws:sns:eu-west-2:111122223333:other-alerts"
    }
  }

  override_resource {
    target = aws_cloudwatch_metric_alarm.dlq_not_empty
    values = {
      arn = "arn:aws:cloudwatch:eu-west-2:111122223333:alarm:other-scan-dlq-not-empty"
    }
  }

  assert {
    condition     = try(toset(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_actions), toset([])) == toset(["arn:aws:sns:eu-west-2:111122223333:other-alerts"])
    error_message = "alarm_actions must hold the arn of aws_sns_topic.alerts, not fixed text (got ${jsonencode(try(aws_cloudwatch_metric_alarm.dlq_not_empty.alarm_actions, []))})."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.alerts_topic.statement : st
      if st.sid == "AllowDlqAlarmToPublish" &&
      toset(st.resources) == toset(["arn:aws:sns:eu-west-2:111122223333:other-alerts"]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : toset(c.values) == toset(["arn:aws:cloudwatch:eu-west-2:111122223333:alarm:other-scan-dlq-not-empty"])])
    ]) == 1
    error_message = "The alarm's policy statement must take its resource from the topic's arn and its aws:SourceArn from the alarm's arn, not fixed text."
  }
}
