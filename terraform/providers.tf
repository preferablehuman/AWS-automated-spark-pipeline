terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # Optional: remote state backend (S3 + DynamoDB)
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "cloud-project/nyu-taxi/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "your-tf-lock-table"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}
