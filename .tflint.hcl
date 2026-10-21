plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Modules declare their contract inputs before the milestone that uses them,
# so "declared but not used" is expected until integration. Turn this back on
# in the INT PR.
rule "terraform_unused_declarations" {
  enabled = false
}
