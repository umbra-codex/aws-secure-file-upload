# ==========================================
# CLOUDWATCH LOG GROUP
# ==========================================

resource "aws_cloudwatch_log_group" "upload_url" {
  name              = "/aws/lambda/${var.project_name}-upload-url"
  retention_in_days = 14

  tags = {
    Name      = "/aws/lambda/${var.project_name}-upload-url"
    Role      = "upload-url"
    ManagedBy = "terraform"
  }
}

# ==========================================
# PACKAGE PYTHON LAMBDA
# ==========================================

data "archive_file" "upload_url" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/upload_url.zip"
}

# ==========================================
# UPLOAD URL LAMBDA FUNCTION
# ==========================================

resource "aws_lambda_function" "upload_url" {
  function_name = "${var.project_name}-upload-url"

  role    = aws_iam_role.upload_url.arn
  runtime = "python3.13"
  handler = "handler.handler"

  filename         = data.archive_file.upload_url.output_path
  source_code_hash = data.archive_file.upload_url.output_base64sha256

  architectures = ["arm64"]

  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      TABLE_NAME    = var.table_name
      BUCKET_NAME   = var.incoming_bucket_name
      ALLOWED_TYPES = join(",", var.allowed_types)
      MAX_SIZE_MB   = var.max_size_mb
    }
  }

  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    log_group             = aws_cloudwatch_log_group.upload_url.name
  }

  tags = {
    Name      = "${var.project_name}-upload-url"
    Role      = "upload-url"
    ManagedBy = "terraform"
  }
}