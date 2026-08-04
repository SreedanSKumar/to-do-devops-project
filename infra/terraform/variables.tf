variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project name used as a prefix/tag on every resource"
  type        = string
  default     = "opsboard"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "opsboard_admin"
}

variable "db_name" {
  type    = string
  default = "opsboard"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "opsboard"
    ManagedBy = "terraform"
  }
}
