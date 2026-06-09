# Account-level configuration for the dev environment.
# account_id is read from the AWS_ACCOUNT_ID env var (set by CI) with a local fallback.
locals {
  account_id   = get_env("AWS_ACCOUNT_ID", "522826274343")
  account_name = "dev"
}
