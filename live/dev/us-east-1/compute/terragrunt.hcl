# Child Terragrunt config for the compute layer in dev/us-east-1.
# Inherits all root settings via include "root" and wires the VPC dependency.

terraform {
  source = "../../../../modules//compute"
}

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

# ---------------------------------------------------------------------------
# Dependency: VPC layer
# mock_outputs lets terragrunt plan succeed before the vpc state exists.
# mock_outputs_allowed_applies = false prevents a real apply using fake IDs.
# ---------------------------------------------------------------------------
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-0000000000000001", "subnet-0000000000000002", "subnet-0000000000000003"]
  }

  mock_outputs_allowed_terraform_commands  = ["plan", "validate"]
}

# ---------------------------------------------------------------------------
# Inputs passed into the compute module.
# ingress_rules and task_definitions use maps — no positional indices.
# ---------------------------------------------------------------------------
inputs = {
  cluster_name = "dev-ecs-cluster"
  environment  = "dev"
  vpc_id       = dependency.vpc.outputs.vpc_id
  subnet_ids   = dependency.vpc.outputs.private_subnets

  container_insights_enabled = true

  ingress_rules = {
    https = {
      description = "HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    http = {
      description = "HTTP from internet (redirect to HTTPS)"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    internal_api = {
      description = "Internal API calls between services"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }
  }

  task_definitions = {
    api = {
      image         = "nginx:1.27-alpine"
      cpu           = 256
      memory        = 512
      port          = 80
      desired_count = 1
      min_capacity  = 1
      max_capacity  = 4
      environment_vars = {
        APP_ENV  = "dev"
        LOG_LEVEL = "info"
      }
    }
    worker = {
      image         = "busybox:1.36"
      cpu           = 256
      memory        = 512
      port          = 0
      desired_count = 1
      min_capacity  = 1
      max_capacity  = 2
      environment_vars = {
        APP_ENV  = "dev"
        LOG_LEVEL = "debug"
      }
    }
  }

  tags = {
    Team        = "platform"
    CostCenter  = "engineering"
    DataClass   = "internal"
  }
}
