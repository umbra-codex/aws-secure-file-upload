# C1 step 1: modules/scanning/iam.tf, the GuardDuty role and its permissions.
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

run "guardduty_role" {
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

  assert {
    condition     = aws_iam_role.guardduty.name == "demo-guardduty"
    error_message = "aws_iam_role.guardduty must be named <project_name>-guardduty (got ${aws_iam_role.guardduty.name})."
  }

  assert {
    condition     = aws_iam_role.guardduty.assume_role_policy == data.aws_iam_policy_document.assume.json
    error_message = "The role's assume_role_policy must reference the json of data.aws_iam_policy_document.assume."
  }

  assert {
    condition = length(data.aws_iam_policy_document.assume.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.assume.statement :
      st.effect == "Allow" && toset(st.actions) == toset(["sts:AssumeRole"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["malware-protection-plan.guardduty.amazonaws.com"])])
    ])
    error_message = "data.aws_iam_policy_document.assume needs one statement: Allow sts:AssumeRole for principal type \"Service\", identifiers [\"malware-protection-plan.guardduty.amazonaws.com\"]."
  }

  assert {
    condition     = lookup(aws_iam_role.guardduty.tags, "Name", "") == "demo-guardduty" && lookup(aws_iam_role.guardduty.tags, "Role", "") == "guardduty" && lookup(aws_iam_role.guardduty.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_iam_role.guardduty needs tags Name = \"demo-guardduty\", Role = \"guardduty\", ManagedBy = \"terraform\" (got ${jsonencode(aws_iam_role.guardduty.tags)})."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.permissions.statement) == 7
    error_message = "The permissions document must have exactly seven statements, the ones in the brief's table (got ${length(data.aws_iam_policy_document.permissions.statement)}). Nothing else: no kms:*, no wildcard actions."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowManagedRuleToSendS3EventsToGuardDuty" && st.effect == "Allow" &&
      toset(st.actions) == toset(["events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets"]) &&
      toset(st.resources) == toset(["arn:aws:events:us-east-1:210987654321:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]) &&
      length(st.condition) == 1 && alltrue([for c in st.condition : c.test == "StringLike" && c.variable == "events:ManagedBy" && toset(c.values) == toset(["malware-protection-plan.guardduty.amazonaws.com"])])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowManagedRuleToSendS3EventsToGuardDuty: Allow events:PutRule, events:DeleteRule, events:PutTargets, events:RemoveTargets on the DO-NOT-DELETE rule ARN (region and account from the two data sources), with condition StringLike events:ManagedBy = malware-protection-plan.guardduty.amazonaws.com."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowGuardDutyToMonitorEventBridgeManagedRule" && st.effect == "Allow" &&
      toset(st.actions) == toset(["events:DescribeRule", "events:ListTargetsByRule"]) &&
      toset(st.resources) == toset(["arn:aws:events:us-east-1:210987654321:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"]) &&
      length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowGuardDutyToMonitorEventBridgeManagedRule: Allow events:DescribeRule and events:ListTargetsByRule on the DO-NOT-DELETE rule ARN, with no condition."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowPostScanTag" && st.effect == "Allow" &&
      toset(st.actions) == toset(["s3:PutObjectTagging", "s3:GetObjectTagging", "s3:PutObjectVersionTagging", "s3:GetObjectVersionTagging"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/*"]) && length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowPostScanTag: Allow s3:PutObjectTagging, s3:GetObjectTagging, s3:PutObjectVersionTagging, s3:GetObjectVersionTagging on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowEnableS3EventBridgeEvents" && st.effect == "Allow" &&
      toset(st.actions) == toset(["s3:PutBucketNotification", "s3:GetBucketNotification"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321"]) && length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowEnableS3EventBridgeEvents: Allow s3:PutBucketNotification and s3:GetBucketNotification on the incoming_bucket_arn variable itself (no /*)."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowPutValidationObject" && st.effect == "Allow" &&
      toset(st.actions) == toset(["s3:PutObject"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/malware-protection-resource-validation-object"]) && length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowPutValidationObject: Allow s3:PutObject on the incoming_bucket_arn variable followed by /malware-protection-resource-validation-object, and nothing broader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowCheckBucketOwnership" && st.effect == "Allow" &&
      toset(st.actions) == toset(["s3:ListBucket"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321"]) && length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowCheckBucketOwnership: Allow s3:ListBucket on the incoming_bucket_arn variable itself (no /*)."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "AllowMalwareScan" && st.effect == "Allow" &&
      toset(st.actions) == toset(["s3:GetObject", "s3:GetObjectVersion"]) &&
      toset(st.resources) == toset(["arn:aws:s3:::demo-incoming-210987654321/*"]) && length(st.condition) == 0
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement AllowMalwareScan: Allow s3:GetObject and s3:GetObjectVersion on the incoming_bucket_arn variable followed by /*."
  }

  assert {
    condition     = aws_iam_role_policy.guardduty.name == "demo-guardduty" && aws_iam_role_policy.guardduty.role == aws_iam_role.guardduty.id && aws_iam_role_policy.guardduty.policy == data.aws_iam_policy_document.permissions.json
    error_message = "aws_iam_role_policy.guardduty must be named <project_name>-guardduty and reference the role's id and the permissions document's json."
  }
}

# Nothing in the permissions may be fixed text: give the two data sources and
# the bucket other values and every resource must follow.
run "permissions_follow_their_inputs" {
  module {
    source = "./modules/scanning"
  }

  variables {
    project_name         = "demo"
    incoming_bucket_name = "other-bucket"
    incoming_bucket_arn  = "arn:aws:s3:::other-bucket"
    router_lambda_arn    = "arn:aws:lambda:us-east-1:210987654321:function:demo-router"
    alert_email          = "alerts@example.com"
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-2"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "999988887777"
    }
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if contains(["AllowManagedRuleToSendS3EventsToGuardDuty", "AllowGuardDutyToMonitorEventBridgeManagedRule"], st.sid) &&
      toset(st.resources) == toset(["arn:aws:events:eu-west-2:999988887777:rule/DO-NOT-DELETE-AmazonGuardDutyMalwareProtectionS3*"])
    ]) == 2
    error_message = "Statements 1 and 2 must build the managed-rule ARN from the region of data.aws_region.current and the account_id of data.aws_caller_identity.current, not from fixed text."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if(contains(["AllowPostScanTag", "AllowMalwareScan"], st.sid) && toset(st.resources) == toset(["arn:aws:s3:::other-bucket/*"])) ||
      (contains(["AllowEnableS3EventBridgeEvents", "AllowCheckBucketOwnership"], st.sid) && toset(st.resources) == toset(["arn:aws:s3:::other-bucket"])) ||
      (st.sid == "AllowPutValidationObject" && toset(st.resources) == toset(["arn:aws:s3:::other-bucket/malware-protection-resource-validation-object"]))
    ]) == 5
    error_message = "Statements 3 to 7 must build their resources from the incoming_bucket_arn variable, not from fixed text."
  }
}
