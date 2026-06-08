# Root Terragrunt configuration — inherited by all child modules via include "root"
# Implements: DRY remote state, dynamic provider generation, and path-based context parsing.

locals {
  # Derive environment, region, and component from the relative directory path.
  # Structure assumed: live/<env>/<region>/<component>
  path_parts  = split("/", path_relative_to_include())
  environment = local.path_parts[0]
  aws_region  = local.path_parts[1]
  component   = local.path_parts[2]

  # Load hierarchical configuration layers. These files define account and region locals.
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_id   = local.account_vars.locals.account_id
  account_name = local.account_vars.locals.account_name
}

# ---------------------------------------------------------------------------
# Remote State — S3 backend with DynamoDB locking, generated per component.
# Bucket and lock table are named deterministically from account + region.
# ---------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "tfstate-${local.account_id}-${local.aws_region}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = "terraform-locks-${local.account_id}"

    skip_bucket_versioning         = false
    skip_bucket_ssencryption       = false
    skip_bucket_root_access        = true
    skip_bucket_enforced_tls       = true
    enable_lock_table_ssencryption = true
  }
}

# ---------------------------------------------------------------------------
# Provider Generation — eliminates repeated provider blocks in every module.
# Injects default_tags so every resource is automatically tagged.
# ---------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      default_tags {
        tags = {
          Environment = "${local.environment}"
          AccountName = "${local.account_name}"
          Component   = "${local.component}"
          ManagedBy   = "Terragrunt"
          Repository  = "terraform-enterprise-blueprint"
        }
      }
    }
  EOF
}

# ---------------------------------------------------------------------------
# Terraform version constraints — enforced globally across all components.
# ---------------------------------------------------------------------------
terraform {
  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=10m"]
  }

  extra_arguments "parallelism" {
    commands  = ["apply", "plan", "destroy"]
    arguments = ["-parallelism=15"]
  }
}
