# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "alb_dns_name" {
  description = "ALB DNS name — create a CNAME record pointing your domain here"
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "Base URL for the REST API"
  value = var.acm_certificate_arn != "" && var.domain_name != "" ? (
    "https://${var.domain_name}"
  ) : "http://${aws_lb.main.dns_name}"
}

output "websocket_url" {
  description = "WebSocket endpoint — connect with ?token=<jwt>"
  value = var.acm_certificate_arn != "" && var.domain_name != "" ? (
    "wss://${var.domain_name}/ws/chat"
  ) : "ws://${aws_lb.main.dns_name}/ws/chat"
}

output "app_elastic_ip" {
  description = "EC2 Elastic IP — for direct SSH or SSM access"
  value       = aws_eip.app.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID — use for SSM Session Manager"
  value       = aws_instance.app.id
}

output "rds_endpoint" {
  description = "RDS host:port (only reachable from within the VPC)"
  value       = "${aws_db_instance.main.address}:${aws_db_instance.main.port}"
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint (only reachable from within the VPC)"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "uploads_bucket_name" {
  description = "S3 bucket for user-uploaded files"
  value       = aws_s3_bucket.uploads.id
}

output "artifacts_bucket_name" {
  description = "S3 bucket for deployment JARs — upload here before deploying"
  value       = aws_s3_bucket.artifacts.id
}

output "deploy_instructions" {
  description = "Step-by-step deploy commands"
  value       = <<-EOT

  ── Build & Deploy ───────────────────────────────────────────────────

  1. Build JARs:
     mvn clean package -DskipTests

  2. Upload to S3:
     aws s3 cp chatrix-api/target/chatrix-api-1.0.0-SNAPSHOT.jar \
       s3://${aws_s3_bucket.artifacts.id}/chatrix-api.jar

     aws s3 cp chatrix-websocket/target/chatrix-websocket-1.0.0-SNAPSHOT-jar-with-dependencies.jar \
       s3://${aws_s3_bucket.artifacts.id}/chatrix-websocket.jar

  3. Connect to EC2 via SSM Session Manager (no SSH key required):
     aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}

  4. Deploy on EC2:
     sudo aws s3 cp s3://${aws_s3_bucket.artifacts.id}/chatrix-api.jar       /opt/chatrix/chatrix-api.jar
     sudo aws s3 cp s3://${aws_s3_bucket.artifacts.id}/chatrix-websocket.jar /opt/chatrix/chatrix-websocket.jar
     sudo chown chatrix:chatrix /opt/chatrix/*.jar
     sudo systemctl restart chatrix-api chatrix-websocket
     sudo systemctl status  chatrix-api chatrix-websocket

  5. Tail logs:
     sudo journalctl -fu chatrix-api
     sudo journalctl -fu chatrix-websocket

  ── Required app.yml change (Redis TLS) ─────────────────────────────

  Add to application.yml or SSM /chatrix/spring.data.redis.ssl.enabled:
    spring.data.redis.ssl.enabled: true

  (Already set in SSM Parameter Store by Terraform)

  ─────────────────────────────────────────────────────────────────────
  EOT
}

output "env_manager_function_name" {
  description = "Lambda function name for manual environment control"
  value       = aws_lambda_function.env_manager.function_name
}

output "env_manager_function_url" {
  description = "Lambda Function URL (requires AWS SigV4 auth)"
  value       = aws_lambda_function_url.env_manager.function_url
}

output "manual_control_commands" {
  description = "AWS CLI commands to manually start/stop/override the environment"
  value       = <<-EOT

  ── Manual Environment Control ───────────────────────────────────────

  FUNCTION: ${aws_lambda_function.env_manager.function_name}
  REGION  : ${var.aws_region}

  # Check current status
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"status"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  # Start everything (immediate — ignores schedule)
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"start"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  # Stop everything (EC2 + RDS only, Redis stays running)
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"stop"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  # Stop everything including Redis (takes ~5 min to restart)
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"stop","include_redis":true}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  ── Schedule Override ─────────────────────────────────────────────────

  # Force ON — keep running even during scheduled off-hours + start now
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"override","value":"force_on"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  # Force OFF — keep stopped even during scheduled on-hours + stop now
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"override","value":"force_off"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  # Resume normal schedule
  aws lambda invoke --region ${var.aws_region} \
    --function-name ${aws_lambda_function.env_manager.function_name} \
    --payload '{"action":"override","value":"none"}' \
    --cli-binary-format raw-in-base64-out /dev/stdout

  ── Shortcut: set override directly via SSM (no Lambda invoke needed) ──

  # Force ON (just pause the schedule — does NOT start EC2/RDS automatically)
  aws ssm put-parameter --region ${var.aws_region} \
    --name "/chatrix/schedule/override" --value "force_on" --overwrite

  # Resume schedule
  aws ssm put-parameter --region ${var.aws_region} \
    --name "/chatrix/schedule/override" --value "none" --overwrite

  ─────────────────────────────────────────────────────────────────────
  EOT
}

output "schedule_info" {
  description = "Active schedule summary"
  value       = <<-EOT
  Schedule enabled : ${var.enable_schedule}
  Stop  (JST)      : ${var.schedule_stop_cron}
  Start (JST)      : ${var.schedule_start_cron}
  Redis stop       : ${var.enable_redis_stop}

  With default schedule (8h/day, Mon–Fri):
    EC2  savings  : ~$8.7/month  ($12 → ~$3.3)
    RDS  savings  : ~$13/month   ($18 → ~$5)
    Redis savings : ~$14/month   (only if enable_redis_stop = true)
    ──────────────────────────────────────
    Total savings : ~$22–35/month
    New estimate  : ~$41–54/month (vs $76 always-on)
  EOT
}

output "estimated_monthly_cost_usd" {
  description = "Rough monthly cost estimate (ap-northeast-1, on-demand)"
  value       = <<-EOT
  ── Always-on baseline ───────────────────────────────
  EC2  t4g.small        ~$12
  RDS  db.t3.micro      ~$18
  Redis cache.t3.micro  ~$14
  ALB  (base + LCU)     ~$18
  EBS  20 GB gp3        ~$ 2
  RDS  20 GB storage    ~$ 3
  S3   (minimal)        ~$ 1
  SSM VPC endpoints     ~$ 7
  CloudWatch logs       ~$ 1
  Lambda (schedule)     ~$ 0  (well within free tier)
  ─────────────────────────────────────────────────────
  Always-on total       ~$76/month

  ── With schedule (8h/day weekdays) + Redis stop ─────
  EC2                   ~$ 3
  RDS  (compute only)   ~$ 5
  Redis                 ~$ 0  (deleted off-hours)
  ALB                   ~$18  (always running)
  Storage / other       ~$14
  ─────────────────────────────────────────────────────
  Scheduled total       ~$40/month  (saves ~$36/month)
  EOT
}
