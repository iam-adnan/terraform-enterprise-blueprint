# ---------------------------------------------------------------------------
# Core identity inputs
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the ECS cluster. Must be lowercase alphanumeric with hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,255}$", var.cluster_name))
    error_message = "cluster_name must be 1-255 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment. Controls resource naming and scaling defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Network inputs — sourced from the vpc dependency layer
# ---------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID of the VPC where the cluster security group will be placed."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid AWS VPC ID (e.g. vpc-0a1b2c3d4e5f)."
  }
}

variable "subnet_ids" {
  description = "List of private subnet IDs for ECS task placement. Minimum 2 for HA."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet_ids are required for high availability."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "All subnet_ids must be valid AWS subnet IDs (e.g. subnet-0a1b2c3d)."
  }
}

# ---------------------------------------------------------------------------
# Security group ingress rules — map-keyed to avoid index-based destruction
# ---------------------------------------------------------------------------

variable "ingress_rules" {
  description = "Map of ingress rules for the ECS security group. Keyed by rule name."
  type = map(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, rule in var.ingress_rules :
      rule.from_port >= 0 && rule.from_port <= 65535
    ])
    error_message = "All ingress rule from_port values must be between 0 and 65535."
  }

  validation {
    condition = alltrue([
      for name, rule in var.ingress_rules :
      rule.to_port >= rule.from_port
    ])
    error_message = "to_port must be greater than or equal to from_port in all ingress rules."
  }
}

# ---------------------------------------------------------------------------
# ECS task definitions — map-keyed for safe for_each iteration
# ---------------------------------------------------------------------------

variable "task_definitions" {
  description = "Map of ECS task definitions. Each key becomes the ECS service name."
  type = map(object({
    image                    = string
    cpu                      = number
    memory                   = number
    port                     = number
    desired_count            = number
    min_capacity             = number
    max_capacity             = number
    environment_vars         = map(string)
    readonly_root_filesystem = optional(bool, false)
    run_as_user              = optional(string, null)
  }))

  validation {
    condition = alltrue([
      for name, td in var.task_definitions :
      td.cpu >= 256 && contains([256, 512, 1024, 2048, 4096, 8192, 16384], td.cpu)
    ])
    error_message = "ECS Fargate cpu must be one of: 256, 512, 1024, 2048, 4096, 8192, 16384."
  }

  validation {
    condition = alltrue([
      for name, td in var.task_definitions :
      td.min_capacity <= td.desired_count && td.desired_count <= td.max_capacity
    ])
    error_message = "desired_count must be between min_capacity and max_capacity for all task definitions."
  }

  validation {
    condition = alltrue([
      for name, td in var.task_definitions :
      td.memory >= td.cpu / 2
    ])
    error_message = "Task memory must be at least half the allocated CPU units (Fargate constraint)."
  }
}

# ---------------------------------------------------------------------------
# Optional feature flags
# ---------------------------------------------------------------------------

variable "container_insights_enabled" {
  description = "Enable CloudWatch Container Insights on the ECS cluster."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional resource tags merged with provider default_tags."
  type        = map(string)
  default     = {}
}
