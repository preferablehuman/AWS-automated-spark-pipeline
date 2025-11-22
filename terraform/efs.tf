#########################
# EFS: shared storage for Spark (ECS) and Lambda
#########################

# Main EFS filesystem
resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-efs"

  encrypted = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.project_name}-efs"
  }
}

# Mount targets in each PRIVATE subnet
resource "aws_efs_mount_target" "private" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.main.id]

  # SG already allows NFS 2049 from itself, so ECS/Lambda with same SG can mount
}

# Access point for app-level isolation
resource "aws_efs_access_point" "spark" {
  file_system_id = aws_efs_file_system.main.id

  # This is the logical "root" you'll mount into ECS/Lambda.
  # Inside the container, you'll map this to /mnt/efs and then
  # your app can use /mnt/efs/incoming and /mnt/efs/checkpoints.
  root_directory {
    path = "/spark"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0777"
    }
  }

  posix_user {
    uid = 1000
    gid = 1000
  }

  tags = {
    Name = "${var.project_name}-efs-ap-spark"
  }
}
