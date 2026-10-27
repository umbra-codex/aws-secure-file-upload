#!/usr/bin/env bash
# Create the state bucket from the README's step 3 and the two ignored local
# files step 4 needs, without relying on shell variables.
#
#   scripts/bootstrap-state.sh
#
# Idempotent, and every value is read from AWS or from terraform.tfvars rather
# than carried in a shell, so a closed terminal, a new window, or a fresh clone
# loses nothing: run it again and it picks up where it left off.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="${PROJECT:-secure-upload}" # must match project_name
REGION="${AWS_REGION:-us-east-1}"

# terraform.tfvars wins over the default, so the bucket name follows the project.
if [ -f terraform.tfvars ]; then
  from_file=$(sed -n 's/^project_name *= *"\([^"]*\)".*/\1/p' terraform.tfvars | head -1)
  [ -n "${from_file:-}" ] && PROJECT="$from_file"
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-${ACCOUNT}-tfstate"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "state bucket already exists: $BUCKET"
else
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  echo "created state bucket: $BUCKET"
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "versioning on, public access blocked"

if [ -f backend.hcl ]; then
  sed -i "s|^bucket .*|bucket       = \"$BUCKET\"|" backend.hcl
  echo "backend.hcl updated: $BUCKET"
else
  sed "s|^bucket .*|bucket       = \"$BUCKET\"|" backend.hcl.example > backend.hcl
  echo "backend.hcl written: $BUCKET"
fi

if [ -f terraform.tfvars ]; then
  echo "terraform.tfvars left as it is"
else
  cp terraform.tfvars.example terraform.tfvars
  echo "terraform.tfvars written from the example"
fi

# owner is a fact about the machine, not a decision: fill it from gh when the
# placeholder is still there. alert_email is the reader's, so it stays a prompt.
if grep -q '^owner *= *"your-github-handle"' terraform.tfvars &&
   login=$(gh api user --jq .login 2>/dev/null) && [ -n "$login" ]; then
  sed -i "s|^owner *= *\"your-github-handle\"|owner        = \"$login\"|" terraform.tfvars
  echo "owner set to $login from gh"
fi

cat <<'EOF'

Next:
  1. Set owner and alert_email in terraform.tfvars (project_name is already set).
  2. terraform init -backend-config=backend.hcl
  3. terraform plan
EOF
