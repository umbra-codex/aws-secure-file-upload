data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${data.aws_caller_identity.current.account_id}"
}

module "incoming" {
  source               = "./bucket"
  bucket_name          = "${local.name_prefix}-incoming"
  enable_versioning    = true
  cors_allowed_origins = var.cors_allowed_origins
  expiration_days      = 1

  tags = {
    Name      = "${local.name_prefix}-incoming"
    Role      = "incoming"
    ManagedBy = "terraform"
  }
}

module "approved" {
  source      = "./bucket"
  bucket_name = "${local.name_prefix}-approved"

  tags = {
    Name      = "${local.name_prefix}-approved"
    Role      = "approved"
    ManagedBy = "terraform"
  }
}

module "quarantine" {
  source          = "./bucket"
  bucket_name     = "${local.name_prefix}-quarantine"
  expiration_days = 30

  tags = {
    Name      = "${local.name_prefix}-quarantine"
    Role      = "quarantine"
    ManagedBy = "terraform"
  }
}
