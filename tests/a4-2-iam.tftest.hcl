# A4 step 2: modules/status/iam.tf, the status Lambda's role and permissions.
# Brief: docs/milestones/A4.md

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  # A3 adds a bucket policy built from this data source. The mock would fake
  # its JSON with random text, which the bucket policy rejects.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "status_role" {
  module {
    source = "./modules/status"
  }

  variables {
    project_name      = "demo"
    table_name        = "demo-uploads"
    table_arn         = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    api_id            = "demo-api-id"
    api_execution_arn = "arn:aws:execute-api:us-east-1:210987654321:demo-api-id"
  }

  # The mock would give these random, identical values. Pin distinct ones so
  # a reference to the wrong attribute fails.
  override_resource {
    target = aws_iam_role.status
    values = {
      id  = "mock-role-id"
      arn = "arn:aws:iam::210987654321:role/demo-status"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.status
    values = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-status"
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
    condition     = aws_iam_role.status.name == "demo-status"
    error_message = "aws_iam_role.status must be named <project_name>-status (got ${aws_iam_role.status.name})."
  }

  assert {
    condition     = aws_iam_role.status.assume_role_policy == data.aws_iam_policy_document.assume.json
    error_message = "The role's assume_role_policy must reference the json of data.aws_iam_policy_document.assume."
  }

  assert {
    condition = length(data.aws_iam_policy_document.assume.statement) == 1 && alltrue([
      for st in data.aws_iam_policy_document.assume.statement :
      st.effect == "Allow" && toset(st.actions) == toset(["sts:AssumeRole"]) &&
      length(st.principals) == 1 && alltrue([for p in st.principals : p.type == "Service" && toset(p.identifiers) == toset(["lambda.amazonaws.com"])])
    ])
    error_message = "data.aws_iam_policy_document.assume needs one statement: Allow sts:AssumeRole for principal type \"Service\", identifiers [\"lambda.amazonaws.com\"]."
  }

  assert {
    condition     = lookup(aws_iam_role.status.tags, "Name", "") == "demo-status" && lookup(aws_iam_role.status.tags, "Role", "") == "status" && lookup(aws_iam_role.status.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_iam_role.status needs tags Name = \"demo-status\", Role = \"status\", ManagedBy = \"terraform\" (got ${jsonencode(aws_iam_role.status.tags)})."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "ReadUploads" && st.effect == "Allow" && toset(st.actions) == toset(["dynamodb:GetItem"]) && toset(st.resources) == toset(["arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement ReadUploads: Allow dynamodb:GetItem on the table_arn variable, and nothing broader."
  }

  assert {
    condition = length([
      for st in data.aws_iam_policy_document.permissions.statement : st
      if st.sid == "WriteLogs" && st.effect == "Allow" && toset(st.actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && toset(st.resources) == toset(["arn:aws:logs:us-east-1:210987654321:log-group:/aws/lambda/demo-status:*"])
    ]) == 1
    error_message = "data.aws_iam_policy_document.permissions needs statement WriteLogs: Allow logs:CreateLogStream and logs:PutLogEvents on the log group's arn followed by :*."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.permissions.statement) == 2
    error_message = "The permissions document must have exactly two statements (ReadUploads and WriteLogs). Least privilege: nothing else."
  }

  assert {
    condition     = aws_iam_role_policy.status.role == aws_iam_role.status.id && aws_iam_role_policy.status.policy == data.aws_iam_policy_document.permissions.json
    error_message = "aws_iam_role_policy.status must reference the role's id and the permissions document's json."
  }
}
