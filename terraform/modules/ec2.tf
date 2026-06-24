# ---------------------------------------------------------------------------
# EC2 App Server
# Runs both chatrix-api (port 8080) and chatrix-websocket (port 8081)
# as systemd services on a single t4g.small instance.
# ---------------------------------------------------------------------------

resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type

  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  key_name = var.ec2_key_name != "" ? var.ec2_key_name : null

  # Disable public IP — traffic goes through ALB; EIP handles admin access
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20    # OS (6 GB) + JARs (50 MB each) + uploads + headroom
    throughput            = 125   # gp3 default — no extra cost
    iops                  = 3000  # gp3 default — no extra cost
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region       = var.aws_region
    artifacts_bucket = aws_s3_bucket.artifacts.id
    log_group        = aws_cloudwatch_log_group.app.name
  })

  # Wait for SSM params and S3 buckets to exist before bootstrapping
  depends_on = [
    aws_ssm_parameter.db_url,
    aws_ssm_parameter.db_password,
    aws_ssm_parameter.redis_host,
    aws_ssm_parameter.redis_password,
    aws_ssm_parameter.redis_ssl,
    aws_ssm_parameter.jwt_secret,
    aws_ssm_parameter.storage_upload_dir,
    aws_ssm_parameter.storage_base_url,
    aws_s3_bucket.artifacts,
    aws_iam_instance_profile.ec2,
  ]

  tags = { Name = "${local.name_prefix}-app" }

  lifecycle {
    # Replacing the instance destroys in-flight uploads; use deploy script instead
    ignore_changes = [user_data, ami]
  }
}

# Static public IP — stays the same if instance is stopped/replaced
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-app-eip" }
}

resource "aws_eip_association" "app" {
  instance_id   = aws_instance.app.id
  allocation_id = aws_eip.app.id
}
