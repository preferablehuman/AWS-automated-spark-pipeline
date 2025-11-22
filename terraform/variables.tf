variable "aws_region" {
  description = "AWS region to deploy everything in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "data-injestion-pipeline"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_username" {
  description = "RDS Postgres username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS Postgres password"
  type        = string
  sensitive   = true
}

variable "ecs_spark_image" {
  description = "ECR image URI for the Spark job container"
  type        = string
}

variable "allowed_debug_cidr" {
  description = "CIDR allowed to reach ECS/RDS directly (for debugging). Set to your IP or 0.0.0.0/0 if you want open access (NOT recommended)."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_name" {
  description = "Database name for the RDS Postgres instance"
  type        = string
  default     = "postgres"
}

variable "db_instance_class" {
  description = "Instance class for RDS Postgres"
  type        = string
  default     = "db.t4g.micro" 
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 900  # 15 minutes
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB"
  type        = number
  default     = 512
}
