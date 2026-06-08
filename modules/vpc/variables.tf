variable "name" {
  description = "Name prefix applied to all VPC resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,64}$", var.name))
    error_message = "name must be 1-64 lowercase alphanumeric characters or hyphens."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC (e.g. 10.0.0.0/16)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnets" {
  description = "Map of public subnets. Key is a short label; each value has cidr and az."
  type = map(object({
    cidr = string
    az   = string
  }))

  validation {
    condition     = length(var.public_subnets) >= 1
    error_message = "At least one public subnet is required (for NAT Gateway placement)."
  }
}

variable "private_subnets" {
  description = "Map of private subnets. Key is a short label; each value has cidr and az."
  type = map(object({
    cidr = string
    az   = string
  }))

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "At least two private subnets are required for ECS high availability."
  }
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
