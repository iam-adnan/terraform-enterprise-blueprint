# terraform-enterprise-blueprint

An enterprise-grade Infrastructure as Code platform built with **Terraform 1.9.5** and **Terragrunt 0.67.0**, implementing multi-layer state isolation, DRY configuration inheritance, policy-as-code scanning, and OIDC-based GitOps CI/CD on AWS ECS Fargate.

## Repository Layout

```
terraform-enterprise-blueprint/
├── .github/workflows/
│   ├── terraform-plan.yml      # Security scan + plan on every PR and manual trigger
│   ├── terraform-apply.yml     # Apply on push to main or manual trigger
│   └── terraform-destroy.yml   # Manual-only destroy with confirmation gate
├── modules/
│   ├── vpc/                    # VPC, subnets, IGW, NAT gateway, route tables
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── compute/                # ECS Fargate cluster, services, auto-scaling, alarms
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── live/
│   ├── terragrunt.hcl          # Root: DRY remote state + provider generation
│   └── dev/
│       ├── account.hcl         # Account ID (reads AWS_ACCOUNT_ID env var)
│       └── us-east-1/
│           ├── region.hcl      # Region locals
│           ├── vpc/
│           │   └── terragrunt.hcl   # VPC layer inputs
│           └── compute/
│               └── terragrunt.hcl   # Compute layer — depends on vpc
├── scripts/
│   └── setup-github-vars.sh    # One-shot script to set GitHub Actions Variables
├── .tflint.hcl                 # TFLint rules (AWS plugin, naming, tags)
└── .checkov.yaml               # Checkov policy-as-code config
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  GitHub Actions (OIDC → IAM Role)                   │
│                                                     │
│  PR:   security-scan ──► plan (vpc + compute)       │
│  main: apply-vpc ──────► apply-compute              │
│  manual: destroy-compute ──► destroy-vpc            │
└───────────────────────┬─────────────────────────────┘
                        │ Terraform state
                        ▼
          S3: tfstate-<account>-<region>/
          ├── dev/us-east-1/vpc/terraform.tfstate
          └── dev/us-east-1/compute/terraform.tfstate
          DynamoDB: terraform-locks-<account>

┌─────────────────────────────────────────────────────┐
│  AWS (us-east-1)                                    │
│                                                     │
│  VPC 10.0.0.0/16                                    │
│  ├── Public subnets  (az-a/b/c) + IGW + NAT        │
│  └── Private subnets (az-a/b/c)                     │
│       └── ECS Cluster: dev-ecs-cluster              │
│            ├── Service: api    (nginx, port 80)     │
│            │    └── StepScaling: CPU >75% / <20%    │
│            └── Service: worker (amazonlinux:2023)   │
│                 └── StepScaling: CPU >75% / <20%    │
└─────────────────────────────────────────────────────┘
```

## Key Design Decisions

| Principle | Implementation |
|---|---|
| DRY configuration | Root `live/terragrunt.hcl` auto-generates `backend.tf` and `provider.tf` for every child |
| State isolation | One S3 key per component; shared DynamoDB table for distributed locking |
| No index drift | All `for_each` uses **map keys** — adding/removing resources never destroys unrelated ones |
| Fail-fast validation | `validation` blocks in every variable trap bad inputs before a plan is sent to AWS |
| Secrets-free CI/CD | GitHub OIDC → IAM role; zero static credentials anywhere |
| Policy-as-code | Checkov + TFLint run before `plan` on every PR |
| Auto state backend | CI bootstraps the S3 bucket and DynamoDB table before Terragrunt runs |
| Layer ordering | VPC applies before compute; compute destroys before VPC |

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | 1.9.5 |
| Terragrunt | 0.67.0 |
| AWS CLI | 2.x |
| GitHub CLI (`gh`) | 2.x (for setup script and manual triggers) |

## First-Time Setup

### 1. Create the GitHub OIDC provider and IAM role

```bash
# Create the OIDC identity provider (run once per account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Save your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create the trust policy (replace YOUR_GITHUB_USERNAME)
cat > /tmp/trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
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
  }]
}
EOF

# Create the role
aws iam create-role \
  --role-name github-actions-terragrunt \
  --assume-role-policy-document file:///tmp/trust.json

# Attach required policies
for policy in \
  AmazonEC2FullAccess \
  AutoScalingFullAccess \
  IAMFullAccess \
  AmazonECS_FullAccess \
  CloudWatchFullAccess \
  AmazonVPCFullAccess \
  AmazonDynamoDBFullAccess \
  AmazonS3FullAccess; do
  aws iam attach-role-policy \
    --role-name github-actions-terragrunt \
    --policy-arn arn:aws:iam::aws:policy/${policy}
done

# Add Application Auto Scaling (separate from EC2 AutoScaling)
aws iam put-role-policy \
  --role-name github-actions-terragrunt \
  --policy-name ApplicationAutoScalingFullAccess \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"application-autoscaling:*","Resource":"*"}]}'
```

### 2. Set GitHub Actions Variables

```bash
# Authenticate the GitHub CLI
gh auth login

# Run the setup script (edit values inside first if needed)
chmod +x scripts/setup-github-vars.sh
./scripts/setup-github-vars.sh
```

The script sets three repository variables:

| Variable | Example value |
|---|---|
| `AWS_ACCOUNT_ID` | `00000000000` |
| `AWS_REGION` | `us-east-1` |
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::000000000000:role/github-actions-terragrunt` |

> **Note:** These are GitHub **Variables** (`vars.*`), not Secrets. They are visible in workflow logs and are intentionally non-sensitive.

### 3. Update account ID

If your account ID differs from the default in `live/dev/account.hcl`, the `AWS_ACCOUNT_ID` GitHub variable takes precedence automatically via `get_env()`. No file edit required for CI.

For local runs, edit the fallback value:

```hcl
# live/dev/account.hcl
locals {
  account_id = get_env("AWS_ACCOUNT_ID", "YOUR_ACCOUNT_ID")
}
```

## CI/CD Workflows

### Plan (on every PR or manual)

Triggered automatically on pull requests targeting `main` that touch `live/**` or `modules/**`. Also triggerable manually.

```
security-scan
  ├── Checkov (policy-as-code)        — fails on policy violations
  ├── TFLint (linting + naming rules) — fails on lint errors
  └── [both pass] ──► plan jobs (parallel)
        ├── Terragrunt Plan — live/dev/us-east-1/vpc
        └── Terragrunt Plan — live/dev/us-east-1/compute
              └── Posts diff as PR comment (PR triggers only)
```

### Apply (on push to main or manual)

```
apply-vpc      — terragrunt apply in live/dev/us-east-1/vpc
  └── apply-compute  — terragrunt apply in live/dev/us-east-1/compute
```

### Destroy (manual only, with confirmation)

Requires typing the environment name as a second input to confirm:

```
validate (confirm == environment name)
  └── destroy-compute
        └── destroy-vpc
```

### Trigger workflows from the CLI

```bash
# Plan
gh workflow run terraform-plan.yml \
  --field environment=dev \
  --repo YOUR_GITHUB_USERNAME/terraform-enterprise-blueprint

# Apply
gh workflow run terraform-apply.yml \
  --field environment=dev \
  --repo YOUR_GITHUB_USERNAME/terraform-enterprise-blueprint

# Destroy (type "dev" in both fields to confirm)
gh workflow run terraform-destroy.yml \
  --field environment=dev \
  --field confirm=dev \
  --repo YOUR_GITHUB_USERNAME/terraform-enterprise-blueprint

# Watch any running workflow
gh run watch --repo YOUR_GITHUB_USERNAME/terraform-enterprise-blueprint
```

## Local Development

```bash
# Export credentials (or use aws sso login)
export AWS_PROFILE=your-profile
export AWS_ACCOUNT_ID=522826274343

# Plan individual layers
cd live/dev/us-east-1/vpc
terragrunt plan

cd live/dev/us-east-1/compute
terragrunt plan   # uses mock VPC outputs if vpc state doesn't exist

# Apply (real VPC must exist first; compute mocks are plan-only)
cd live/dev/us-east-1/vpc && terragrunt apply
cd live/dev/us-east-1/compute && terragrunt apply

# Destroy (reverse order)
cd live/dev/us-east-1/compute && terragrunt destroy
cd live/dev/us-east-1/vpc && terragrunt destroy

# Security scan
checkov -d modules/ --config-file .checkov.yaml

# Lint
tflint --init && tflint --recursive --format compact
```

## Modules

### `modules/vpc`

Creates a production-ready VPC with public/private subnet pairs across multiple AZs.

| Resource | Description |
|---|---|
| `aws_vpc` | VPC with DNS hostnames and DNS support enabled |
| `aws_subnet.public` | Public subnets (one per map key), `map_public_ip_on_launch = true` |
| `aws_subnet.private` | Private subnets (one per map key) |
| `aws_internet_gateway` | Internet gateway attached to the VPC |
| `aws_nat_gateway` | Single NAT gateway in the first public subnet |
| `aws_route_table.public` | Routes `0.0.0.0/0` to the internet gateway |
| `aws_route_table.private` | Routes `0.0.0.0/0` through the NAT gateway |

**Key inputs:**

| Variable | Type | Description |
|---|---|---|
| `name` | `string` | Name prefix for all resources |
| `vpc_cidr` | `string` | VPC IPv4 CIDR (e.g. `10.0.0.0/16`) |
| `public_subnets` | `map(object)` | Map of `{ cidr, az }` for public subnets |
| `private_subnets` | `map(object)` | Map of `{ cidr, az }` for private subnets |

**Outputs:** `vpc_id`, `public_subnets` (list of IDs), `private_subnets` (list of IDs)

---

### `modules/compute`

Creates a full ECS Fargate cluster from a single `task_definitions` map input. All resources use `for_each` over map keys — adding or removing a service never impacts other services.

| Resource | Description |
|---|---|
| `aws_ecs_cluster` | ECS cluster with optional Container Insights |
| `aws_ecs_cluster_capacity_providers` | FARGATE + FARGATE_SPOT |
| `aws_ecs_task_definition` | One per map key; supports optional `command`, `readonly_root_filesystem`, `run_as_user` |
| `aws_ecs_service` | One per map key; `desired_count` ignored after first deploy (auto-scaling owns it) |
| `aws_security_group` | Dynamic ingress from `ingress_rules` map |
| `aws_iam_role.execution` | ECS execution role (image pull + log push) |
| `aws_iam_role.task` | Task role (CloudWatch Logs write) |
| `aws_appautoscaling_target` | One per service |
| `aws_appautoscaling_policy.scale_out` | +1 task when CPU > 75% (60s cooldown) |
| `aws_appautoscaling_policy.scale_in` | −1 task when CPU < 20% (300s cooldown) |
| `aws_cloudwatch_metric_alarm.cpu_high` | Triggers scale-out |
| `aws_cloudwatch_metric_alarm.cpu_low` | Triggers scale-in |
| `aws_cloudwatch_log_group` | 14-day retention (dev), 90-day (prod) |

**Key inputs:**

| Variable | Type | Description |
|---|---|---|
| `cluster_name` | `string` | ECS cluster name |
| `environment` | `string` | `dev` / `staging` / `prod` |
| `vpc_id` | `string` | VPC for the security group |
| `subnet_ids` | `list(string)` | Private subnets for task placement (min 2) |
| `task_definitions` | `map(object)` | Services to create (see below) |
| `ingress_rules` | `map(object)` | Security group ingress rules |

**`task_definitions` object shape:**

```hcl
task_definitions = {
  api = {
    image         = "nginx:1.27-alpine"
    cpu           = 256           # Must be valid Fargate CPU value
    memory        = 512
    port          = 80            # 0 = no port mapping (background workers)
    desired_count = 1
    min_capacity  = 1
    max_capacity  = 4
    environment_vars = { APP_ENV = "dev" }
    command       = null          # optional override (e.g. ["/bin/sh", "-c", "..."])
  }
}
```

## Remote State

State is stored in S3 with per-component isolation and DynamoDB locking. The CI bootstrap step creates the bucket and table on first run — no manual setup required.

| Resource | Name pattern |
|---|---|
| S3 bucket | `tfstate-<account_id>-<region>` |
| S3 key | `dev/us-east-1/<component>/terraform.tfstate` |
| DynamoDB table | `terraform-locks-<account_id>` |

**Bucket hardening applied by the bootstrap step:**
- Versioning enabled
- AES-256 server-side encryption
- Public access blocked
- TLS-only bucket policy (denies `aws:SecureTransport = false`)

## Policy-as-Code

### Checkov (`.checkov.yaml`)

Enforced checks (fail the build if violated):

| Check | Description |
|---|---|
| `CKV_AWS_97` | ECS task definitions must not use privileged containers |
| `CKV_AWS_336` | ECS tasks must not run as root |
| `CKV_AWS_249` | ECS task execution role must use least-privilege policies |
| `CKV_AWS_111` | IAM policies must not allow `*` actions |
| `CKV_AWS_355` | CloudWatch log groups must have retention set |
| `CKV2_AWS_28` | ECS services must have auto-scaling enabled |

Skipped (with justification):

| Check | Reason |
|---|---|
| `CKV_AWS_7` | KMS key rotation — acceptable in dev; enforce separately in prod |
| `CKV2_AWS_5` | False positive: SG is dynamically attached, not detectable statically |

### TFLint (`.tflint.hcl`)

- AWS provider plugin v0.32.0
- Enforces `snake_case` naming on all resources and variables
- Requires descriptions on all variables and outputs
- Requires type constraints on all variables
- Requires `terraform_required_version` and `terraform_required_providers`
- Checks `aws_resource_missing_tags` for `Environment` and `ManagedBy` tags
- Disallows unused declarations and deprecated interpolation syntax

## Adding a New Environment

1. Create `live/<env>/account.hcl` with the account ID for that environment.
2. Create `live/<env>/<region>/region.hcl` with the region locals.
3. Copy `live/dev/us-east-1/vpc/terragrunt.hcl` and `live/dev/us-east-1/compute/terragrunt.hcl` into the new path, adjusting CIDR ranges and inputs.
4. Add the new components to the `matrix.component` list in `.github/workflows/terraform-plan.yml`.
5. Add the new environment to the `options` list in all three workflow `workflow_dispatch` inputs.
6. Create a matching GitHub Environment with required reviewers for promotion gates (Settings → Environments).
7. Set `AWS_OIDC_ROLE_ARN` as an environment-level variable if the new environment uses a different AWS account.

## Adding a New Module

1. Create `modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`.
2. Add a `live/<env>/<region>/<name>/terragrunt.hcl` pointing `source` at the new module.
3. Wire cross-layer dependencies using `dependency` blocks with `mock_outputs` and `mock_outputs_allowed_terraform_commands = ["plan", "validate"]`.
4. Add the new component path to the `matrix.component` list in the plan workflow and as a new `apply-<name>` job in the apply workflow, sequenced after its dependency.
