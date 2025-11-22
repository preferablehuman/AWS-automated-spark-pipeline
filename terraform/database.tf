#########################
# RDS: Postgres
#########################

# Subnet group for RDS – use PRIVATE subnets only
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [for s in aws_subnet.public : s.id]

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

resource "aws_db_instance" "rds" {
  identifier = "${var.project_name}-postgres"

  engine = "postgres"
  # Do NOT set engine_version → let AWS pick latest supported version for Postgres in this region.

  instance_class = var.db_instance_class

  allocated_storage    = 40
  max_allocated_storage = 100  # autoscaling headroom; tweak if you want strict 40GB
  storage_type         = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.main.id]

  publicly_accessible = true
  multi_az            = false   # turn on later if you want HA

  # backup_retention_period = 7   # days
  # delete_automated_backups = true

  # For dev: easy to tear down. For prod, set to true and require snapshot.
  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-rds-postgres"
  }
}
