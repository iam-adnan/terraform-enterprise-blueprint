#!/usr/bin/env bash
# Sets all GitHub Actions Variables required by the CI/CD workflows.
# Run once from the root of your cloned repository after `gh auth login`.
#
# Usage:
#   chmod +x scripts/setup-github-vars.sh
#   ./scripts/setup-github-vars.sh

set -euo pipefail

# ─── Edit these values before running ────────────────────────────────────────
AWS_ACCOUNT_ID="522826274343"
AWS_REGION="us-east-1"
# IAM role created for GitHub OIDC — see README for trust policy
AWS_OIDC_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/github-actions-terragrunt"
# ─────────────────────────────────────────────────────────────────────────────

echo "Setting GitHub Actions Variables for repo: $(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo ""

gh variable set AWS_ACCOUNT_ID    --body "${AWS_ACCOUNT_ID}"
echo "  AWS_ACCOUNT_ID    = ${AWS_ACCOUNT_ID}"

gh variable set AWS_REGION        --body "${AWS_REGION}"
echo "  AWS_REGION        = ${AWS_REGION}"

gh variable set AWS_OIDC_ROLE_ARN --body "${AWS_OIDC_ROLE_ARN}"
echo "  AWS_OIDC_ROLE_ARN = ${AWS_OIDC_ROLE_ARN}"

echo ""
echo "Done. Current variables:"
gh variable list
