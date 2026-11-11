resource "aws_guardduty_malware_protection_plan" "incoming" {
  role = aws_iam_role.guardduty.arn

  protected_resource {
    s3_bucket {
      bucket_name     = var.incoming_bucket_name
      object_prefixes = ["uploads/"]
    }
  }

  actions {
    tagging {
      status = "ENABLED"
    }
  }

  tags = {
    Name      = "${var.project_name}-incoming-scan"
    Role      = "guardduty"
    ManagedBy = "terraform"
  }

  depends_on = [aws_iam_role_policy.guardduty]
}