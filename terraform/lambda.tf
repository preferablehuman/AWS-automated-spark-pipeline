#########################
# S3 bucket for incoming CSV files
#########################

resource "random_id" "s3_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "incoming" {
  bucket = "${var.project_name}-incoming-${random_id.s3_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-incoming"
    Environment = "dev"
  }
}

# Lock down public access
resource "aws_s3_bucket_public_access_block" "incoming" {
  bucket = aws_s3_bucket.incoming.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#########################
# IAM for Lambda
#########################

# resource "aws_iam_role" "lambda_data-ingestion" {
#   name = "${var.project_name}-lambda-s3-to-efs-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action    = "sts:AssumeRole",
#         Effect    = "Allow",
#         Principal = { Service = "lambda.amazonaws.com" }
#       }
#     ]
#   })
# }

# # Basic logging + VPC access
# resource "aws_iam_role_policy_attachment" "lambda_basic" {
#   role       = aws_iam_role.lambda_data-ingestion.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
# }

# resource "aws_iam_role_policy_attachment" "lambda_vpc" {
#   role       = aws_iam_role.lambda_data-ingestion.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
# }

# # S3 + EFS permissions
# resource "aws_iam_role_policy" "lambda_s3_efs" {
#   name = "${var.project_name}-lambda-s3-efs-policy"
#   role = aws_iam_role.lambda_data-ingestion.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Sid      = "S3Read"
#         Effect   = "Allow"
#         Action   = [
#           "s3:GetObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           aws_s3_bucket.incoming.arn,
#           "${aws_s3_bucket.incoming.arn}/*"
#         ]
#       },
#       {
#         Sid    = "EFSClientAccess"
#         Effect = "Allow"
#         Action = [
#           "elasticfilesystem:ClientMount",
#           "elasticfilesystem:ClientWrite",
#           "elasticfilesystem:ClientRootAccess"
#         ]
#         Resource = [
#           aws_efs_file_system.main.arn,
#           aws_efs_access_point.spark.arn
#         ]
#       },
#       {
#         Sid    = "EC2NetworkForLambda"
#         Effect = "Allow"
#         Action = [
#           "ec2:CreateNetworkInterface",
#           "ec2:DescribeNetworkInterfaces",
#           "ec2:DeleteNetworkInterface"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# }

#########################
# Lambda function: S3 -> EFS
#########################

resource "aws_lambda_function" "data-ingestion" {
  function_name = "${var.project_name}-s3-to-efs"
  role          = aws_iam_role.lambda_data-ingestion.arn

  runtime = "python3.12"
  handler = "data-ingestion.lambda_handler"

  # You will build this zip: see code example below
  filename         = "${path.module}/lambda/data-ingestion.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/data-ingestion.zip")

  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size
  publish      = true

  # VPC + SG so it can mount EFS
  vpc_config {
    subnet_ids         = [for s in aws_subnet.private : s.id]
    security_group_ids = [aws_security_group.main.id]
  }

  # Mount EFS via access point
  file_system_config {
    arn              = aws_efs_access_point.spark.arn
    local_mount_path = "/mnt/efs"
  }

  environment {
    variables = {
      INCOMING_DIR = "/mnt/efs/incoming"
      BUCKET_NAME  = aws_s3_bucket.incoming.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-s3-to-efs"
  }
  
  depends_on = [
    aws_efs_mount_target.private
  ]
}

#########################
# Allow S3 to invoke Lambda
#########################

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data-ingestion.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.incoming.arn
}

#########################
# S3 -> Lambda notification
#########################

resource "aws_s3_bucket_notification" "incoming" {
  bucket = aws_s3_bucket.incoming.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data-ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    # optional: you can add a prefix/suffix filter later
    # filter_prefix       = "incoming/"
    # filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
