provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost-saver for a demo/capstone; use one-per-AZ in real prod
  enable_dns_hostnames = true

  # Required for the AWS Load Balancer Controller to auto-discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${var.project}-cluster" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.project}-cluster" = "shared"
  }
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.0"

  cluster_name    = "${var.project}-cluster"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
    }
  }

  # So Terraform-applied Helm/Kubernetes resources and your own kubectl/IAM
  # user can both administer the cluster.
  enable_cluster_creator_admin_permissions = true
}

# ---------------------------------------------------------------------------
# Database credentials (generated, not hardcoded)
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 20
  special = false # avoid characters that need URL-encoding in DATABASE_URL
}

# ---------------------------------------------------------------------------
# RDS (Postgres)
# ---------------------------------------------------------------------------
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.9.0"

  identifier = "${var.project}-db"

  engine         = "postgres"
  engine_version = "15.18"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  storage_encrypted     = true
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  port                    = 5432
  manage_master_user_password = false

  create_db_subnet_group  = false
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.rds.id]

  multi_az               = false # set true for real prod HA
  backup_retention_period = 7
  deletion_protection    = false # set true for real prod
  skip_final_snapshot    = true  # set false for real prod

  family = "postgres15"
}
