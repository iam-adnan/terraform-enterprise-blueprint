plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Enforce naming conventions
rule "terraform_naming_convention" {
  enabled = true

  resource {
    format = "snake_case"
  }

  variable {
    format = "snake_case"
  }
}

# Require descriptions on all variables and outputs
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Disallow deprecated attributes
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Require type constraints on all variables
rule "terraform_typed_variables" {
  enabled = true
}

# Disallow unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}

# Enforce required version constraints
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# AWS-specific rules
rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = true
}

rule "aws_resource_missing_tags" {
  enabled = true
  tags    = ["Environment", "ManagedBy"]
}
