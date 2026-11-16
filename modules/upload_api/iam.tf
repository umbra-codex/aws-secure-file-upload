# ==========================================
# 1. LAMBDA TRUST POLICY
# ==========================================

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


# ==========================================
# 2. LAMBDA EXECUTION ROLE
# ==========================================

resource "aws_iam_role" "upload_url" {
  name = "${var.project_name}-upload-url"

  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = {
    Name      = "${var.project_name}-upload-url"
    Role      = "upload-url"
    ManagedBy = "terraform"
  }
}


# ==========================================
# 3. LAMBDA PERMISSIONS POLICY
# ==========================================

data "aws_iam_policy_document" "permissions" {

  # Allow presigned uploads to S3
  statement {
    sid    = "SignUploads"
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${var.incoming_bucket_arn}/uploads/*"
    ]
  }

  # Allow writing upload records to DynamoDB
  statement {
    sid    = "RecordUploads"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem"
    ]

    resources = [
      var.table_arn
    ]
  }

  # Allow writing logs to CloudWatch
  statement {
    sid    = "WriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.upload_url.arn}:*"
    ]
  }
}


# ==========================================
# 4. ATTACH PERMISSIONS TO ROLE
# ==========================================

resource "aws_iam_role_policy" "upload_url" {
  name = "${var.project_name}-upload-url"

  role   = aws_iam_role.upload_url.id
  policy = data.aws_iam_policy_document.permissions.json
}