# A4 step 4: modules/status/api.tf, the route on the team's HTTP API.
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

run "status_route" {
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

  override_resource {
    target = aws_apigatewayv2_integration.status
    values = {
      id = "mock-integration-id"
    }
  }

  assert {
    condition = (
      aws_apigatewayv2_integration.status.api_id == "demo-api-id" &&
      aws_apigatewayv2_integration.status.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.status.payload_format_version == "2.0"
    )
    error_message = "aws_apigatewayv2_integration.status must use the api_id variable, integration_type \"AWS_PROXY\", and payload_format_version \"2.0\"."
  }

  assert {
    condition     = aws_apigatewayv2_integration.status.integration_uri == aws_lambda_function.status.invoke_arn
    error_message = "The integration's integration_uri must reference the function's invoke_arn (not its arn)."
  }

  assert {
    condition     = aws_apigatewayv2_route.status.api_id == "demo-api-id" && aws_apigatewayv2_route.status.route_key == "GET /status/{upload_id}"
    error_message = "aws_apigatewayv2_route.status must use the api_id variable and route_key \"GET /status/{upload_id}\" (got ${aws_apigatewayv2_route.status.route_key})."
  }

  assert {
    condition     = aws_apigatewayv2_route.status.target == "integrations/mock-integration-id"
    error_message = "The route's target must be \"integrations/\" followed by the integration's id (got ${aws_apigatewayv2_route.status.target})."
  }

  assert {
    condition = (
      aws_lambda_permission.api.action == "lambda:InvokeFunction" &&
      aws_lambda_permission.api.principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.api.function_name == aws_lambda_function.status.function_name &&
      aws_lambda_permission.api.source_arn == "arn:aws:execute-api:us-east-1:210987654321:demo-api-id/*/*"
    )
    error_message = "aws_lambda_permission.api must let apigateway.amazonaws.com call lambda:InvokeFunction on the function, with source_arn = the api_execution_arn variable followed by /*/*."
  }
}
