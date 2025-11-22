output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnets" {
  value = [for s in aws_subnet.private : s.id]
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint (host:port)"
  value       = aws_db_instance.rds.endpoint
}

output "rds_db_name" {
  description = "Database name on the RDS instance"
  value       = aws_db_instance.rds.db_name
}

output "rds_jdbc_url" {
  description = "JDBC URL for Spark (use as DB_URL env var)"
  value       = "jdbc:postgresql://${aws_db_instance.rds.endpoint}/${aws_db_instance.rds.db_name}"
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_access_point_arn" {
  description = "ARN of the EFS access point for Spark/Lambda"
  value       = aws_efs_access_point.spark.arn
}

