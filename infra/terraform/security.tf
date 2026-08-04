resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnets"
  subnet_ids = module.vpc.private_subnets
  tags       = { Name = "${var.project}-db-subnets" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Allow Postgres traffic from the EKS node group only"
  vpc_id      = module.vpc.vpc_id

  tags = { Name = "${var.project}-rds-sg" }
}

resource "aws_security_group_rule" "rds_from_eks_nodes" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = module.eks.node_security_group_id
  description               = "Postgres from EKS worker nodes"
}

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}
