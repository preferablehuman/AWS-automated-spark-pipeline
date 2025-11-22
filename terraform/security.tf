resource "aws_security_group" "main" {
  name        = "${var.project_name}-main-sg"
  description = "Single SG for ECS, Lambda, EFS, and RDS internal traffic"
  vpc_id      = aws_vpc.main.id

  # --- Ingress: internal-only via self-references ---

  # NFS for EFS mounts (ECS + Lambda -> EFS)
  ingress {
    description = "NFS from same security group"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    self        = true
  }

  # Postgres for RDS (ECS -> RDS)
  ingress {
    description = "Postgres from same security group"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  # Optional: all internal traffic between members of this SG
  # Uncomment if you want containers, lambda, db, efs to talk on any port internally.
  # ingress {
  #   description = "All internal traffic within this SG"
  #   from_port   = 0
  #   to_port     = 0
  #   protocol    = "-1"
  #   self        = true
  # }

  # --- Egress: allow everything out (to S3, ECR, CloudWatch, etc.) ---

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-main-sg"
  }
}
