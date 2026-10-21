# A4 step 3: modules/status/lambda.tf, the log group, the zip, and the function.
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

run "status_function" {
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

  override_resource {
    target = aws_lambda_function.status
    values = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:demo-status"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:demo-status/invocations"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.status.name == "/aws/lambda/demo-status" && aws_cloudwatch_log_group.status.retention_in_days == 14
    error_message = "aws_cloudwatch_log_group.status must be named /aws/lambda/<project_name>-status with retention_in_days = 14."
  }

  assert {
    condition     = lookup(aws_cloudwatch_log_group.status.tags, "Name", "") == "/aws/lambda/demo-status" && lookup(aws_cloudwatch_log_group.status.tags, "Role", "") == "status" && lookup(aws_cloudwatch_log_group.status.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_log_group.status needs tags Name = \"/aws/lambda/demo-status\", Role = \"status\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_log_group.status.tags)})."
  }

  assert {
    condition     = data.archive_file.status.type == "zip" && endswith(data.archive_file.status.source_dir, "/src") && endswith(data.archive_file.status.output_path, "/build/status.zip")
    error_message = "data.archive_file.status must zip the module's src folder (source_dir = path.module followed by /src) into build/status.zip."
  }

  assert {
    condition = (
      aws_lambda_function.status.function_name == "demo-status" &&
      aws_lambda_function.status.runtime == "python3.13" &&
      aws_lambda_function.status.handler == "handler.handler" &&
      toset(aws_lambda_function.status.architectures) == toset(["arm64"]) &&
      aws_lambda_function.status.timeout == 5 &&
      aws_lambda_function.status.memory_size == 128
    )
    error_message = "aws_lambda_function.status must be named <project_name>-status, with runtime python3.13, handler handler.handler, architectures [\"arm64\"], timeout 5, memory_size 128."
  }

  assert {
    condition     = aws_lambda_function.status.role == "arn:aws:iam::210987654321:role/demo-status"
    error_message = "The function's role must reference the role's arn (got ${aws_lambda_function.status.role})."
  }

  assert {
    condition     = aws_lambda_function.status.filename == data.archive_file.status.output_path && aws_lambda_function.status.source_code_hash == data.archive_file.status.output_base64sha256
    error_message = "The function's filename and source_code_hash must reference the archive's output_path and output_base64sha256, so code changes redeploy."
  }

  assert {
    condition     = lookup(one(aws_lambda_function.status.environment).variables, "TABLE_NAME", "") == "demo-uploads"
    error_message = "The function needs an environment block whose variables include TABLE_NAME = the table_name variable."
  }

  assert {
    condition     = lookup(aws_lambda_function.status.tags, "Name", "") == "demo-status" && lookup(aws_lambda_function.status.tags, "Role", "") == "status" && lookup(aws_lambda_function.status.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_lambda_function.status needs tags Name = \"demo-status\", Role = \"status\", ManagedBy = \"terraform\" (got ${jsonencode(aws_lambda_function.status.tags)})."
  }
}
