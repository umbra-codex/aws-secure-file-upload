# A4 step 5: modules/status/outputs.tf
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

run "status_outputs" {
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
    target = aws_lambda_function.status
    values = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:demo-status"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:demo-status/invocations"
    }
  }

  assert {
    condition     = output.status_role_arn == "arn:aws:iam::210987654321:role/demo-status"
    error_message = "status_role_arn must reference the role's arn (still the placeholder? got ${output.status_role_arn})."
  }

  assert {
    condition     = output.status_function_name == aws_lambda_function.status.function_name && output.status_route_key == aws_apigatewayv2_route.status.route_key
    error_message = "status_function_name and status_route_key must reference the function's function_name and the route's route_key."
  }
}
