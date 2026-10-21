terraform {
  # 1.10+ for S3-native state locking (use_lockfile); mocked providers in
  # `terraform test` need 1.7+. CI runs the version pinned in .github/workflows/ci.yml.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }

    # Zips Lambda source folders (archive_file) so Terraform can deploy them.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }

  # Partial backend: each person supplies their own state bucket at init time.
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example and the README's "Bootstrap" section.
  backend "s3" {}
}
