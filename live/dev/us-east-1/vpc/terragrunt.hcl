terraform {
  source = "../../../../modules//vpc"
}

include "root" {
  path   = find_in_parent_folders()
  expose = true
}

inputs = {
  name     = "dev-vpc"
  vpc_cidr = "10.0.0.0/16"

  public_subnets = {
    "az-a" = { cidr = "10.0.0.0/24", az = "us-east-1a" }
    "az-b" = { cidr = "10.0.1.0/24", az = "us-east-1b" }
    "az-c" = { cidr = "10.0.2.0/24", az = "us-east-1c" }
  }

  private_subnets = {
    "az-a" = { cidr = "10.0.10.0/24", az = "us-east-1a" }
    "az-b" = { cidr = "10.0.11.0/24", az = "us-east-1b" }
    "az-c" = { cidr = "10.0.12.0/24", az = "us-east-1c" }
  }

  tags = {
    Team       = "platform"
    CostCenter = "engineering"
  }
}
