# terraform-enterprise-blueprint

An enterprise-grade Infrastructure as Code platform built with **Terraform** and **Terragrunt**, implementing multi-tier state isolation, DRY configuration inheritance, policy-as-code scanning, and OIDC-based GitOps CI/CD on AWS.

## Architecture Overview

```
terraform-enterprise-blueprint/
├── .github/workflows/
│   ├── terraform-plan.yml     # OIDC plan on every PR
│   └── terraform-apply.yml    # OIDC apply on merge to main
├── modules/
│   └── compute/               # Reusable ECS Fargate module
│       ├── main.tf
│       ├── variables.tf       # Input validation with fail-fast checks
│       ├── outputs.tf
│       └── versions.tf
├── live/
│   ├── terragrunt.hcl         # Root: DRY backend + provider generation
│   └── dev/
│       ├── account.hcl        # Account-level locals
│       └── us-east-1/
│           ├── region.hcl     # Region-level locals
│           └── compute/
│               └── terragrunt.hcl  # Child config with VPC dependency
├── .tflint.hcl                # Linting rules
└── .checkov.yaml              # Policy-as-code scanner config
```

## Key Design Decisions

| Principle | Implementation |
|---|---|
| DRY configuration | Root `live/terragrunt.hcl` auto-generates `backend.tf` and `provider.tf` |
| State isolation | One S3 key per component; DynamoDB distributed locking |
| No index drift | All `for_each` loops use **map keys**, never list indices |
| Fail-fast validation | Variable `validation` blocks trap bad inputs before plan |
| Secrets-free CI/CD | GitHub OIDC → IAM role assumption; zero static credentials |
| Policy-as-code | Checkov + TFLint run on every PR before `plan` executes |

## Prerequisites

| Tool | Minimum Version |
|---|---|
| Terraform | 1.6.0 |
| Terragrunt | 0.67.0 |
| AWS CLI | 2.x |

## First-Time Setup

### 1. Replace placeholder values

```bash
# Set your real AWS account ID in:
live/dev/account.hcl  →  account_id = "YOUR_ACCOUNT_ID"
```

### 2. Bootstrap the S3 state bucket and DynamoDB lock table

The bucket name pattern is `tfstate-<account_id>-<region>`. Create once:

```bash
aws s3api create-bucket \
  --bucket tfstate-YOUR_ACCOUNT_ID-us-east-1 \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket tfstate-YOUR_ACCOUNT_ID-us-east-1 \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name terraform-locks-YOUR_ACCOUNT_ID \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 3. Configure GitHub OIDC

Create an IAM OIDC provider and role for GitHub Actions, then add the role ARN as a repository secret:

```
Settings → Secrets → Actions → New secret
Name:  AWS_OIDC_ROLE_ARN
Value: arn:aws:iam::YOUR_ACCOUNT_ID:role/github-actions-terragrunt
```

Trust policy for the IAM role:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/terraform-enterprise-blueprint:*"
    }
  }
}
```

## Local Development

```bash
# Plan the compute layer
cd live/dev/us-east-1/compute
terragrunt plan

# Apply (requires real VPC — mock_outputs_allowed_applies = false)
terragrunt apply

# Run security scan locally
checkov -d modules/ --config-file .checkov.yaml

# Run linter
tflint --init && tflint --recursive
```

## Adding a New Environment

1. Create `live/<env>/account.hcl` with the new account ID.
2. Create `live/<env>/<region>/region.hcl`.
3. Copy and adjust `live/dev/us-east-1/compute/terragrunt.hcl` into the new path.
4. Add the environment to the `matrix.component` list in `.github/workflows/terraform-plan.yml`.
5. Create a matching GitHub Environment with required reviewers for prod promotion.

## Adding a New Module

1. Create `modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
2. Add a `live/<env>/<region>/<name>/terragrunt.hcl` pointing `source` at the new module.
3. Wire dependencies using `dependency` blocks with `mock_outputs`.

## CI/CD Flow

```
Pull Request opened
  └── security-scan job (Checkov + TFLint)
        └── plan job (terragrunt plan → comment on PR)

Merge to main
  └── apply job (terragrunt apply via OIDC)
        └── Manual approval required for prod (GitHub Environment protection)
```
