# ---------------------------------------------------------------------------
# Lambda — Chatrix Environment Manager
# Handles: start | stop | status | override
# Invoked by: EventBridge Scheduler (scheduled) + Lambda Function URL (manual)
# ---------------------------------------------------------------------------

# ── Package Lambda source code ──────────────────────────────────────────────

data "archive_file" "env_manager" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/env_manager.py"
  output_path = "${path.module}/lambda_src/env_manager.zip"
}

# ── IAM Role ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_env_manager" {
  name = "${local.name_prefix}-lambda-env-manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
      # Allow EventBridge Scheduler to invoke via this role
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = { Name = "${local.name_prefix}-lambda-env-manager-role" }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_env_manager.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_env_manager_policy" {
  name = "${local.name_prefix}-env-manager-policy"
  role = aws_iam_role.lambda_env_manager.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EC2 stop/start/describe
      {
        Sid    = "EC2Control"
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      # RDS stop/start/describe
      {
        Sid    = "RDSControl"
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:DescribeDBInstances",
        ]
        Resource = aws_db_instance.main.arn
      },
      # ElastiCache delete/create/describe
      {
        Sid    = "ElastiCacheControl"
        Effect = "Allow"
        Action = [
          "elasticache:DeleteReplicationGroup",
          "elasticache:CreateReplicationGroup",
          "elasticache:DescribeReplicationGroups",
        ]
        Resource = "*"
      },
      # SSM — read secrets + read/write override param + update Redis endpoint
      {
        Sid    = "SSMReadWrite"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/chatrix/*",
        ]
      },
      # KMS — decrypt SecureString parameters
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
      },
      # Allow EventBridge Scheduler to invoke Lambda (attached to Lambda role for convenience)
      {
        Sid      = "AllowSchedulerInvoke"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-env-manager"
      },
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "env_manager" {
  function_name    = "${local.name_prefix}-env-manager"
  description      = "Start/stop/status Chatrix EC2, RDS, and ElastiCache on schedule or on demand"
  role             = aws_iam_role.lambda_env_manager.arn
  runtime          = "python3.12"
  handler          = "env_manager.lambda_handler"
  filename         = data.archive_file.env_manager.output_path
  source_code_hash = data.archive_file.env_manager.output_base64sha256

  # ElastiCache recreation can take ~5 min — allow up to 10 min
  timeout     = 600
  memory_size = 128 # Python with boto3 fits comfortably in 128 MB

  environment {
    variables = {
      REGION                  = var.aws_region
      EC2_INSTANCE_ID         = aws_instance.app.id
      RDS_IDENTIFIER          = aws_db_instance.main.identifier
      REDIS_GROUP_ID          = aws_elasticache_replication_group.redis.id
      REDIS_NODE_TYPE         = var.redis_node_type
      REDIS_SUBNET_GROUP      = aws_elasticache_subnet_group.main.name
      REDIS_SECURITY_GROUP_ID = aws_security_group.redis.id
      REDIS_PARAM_GROUP       = aws_elasticache_parameter_group.redis7.name
      REDIS_AUTH_TOKEN_PARAM  = aws_ssm_parameter.redis_password.name
      REDIS_HOST_PARAM        = aws_ssm_parameter.redis_host.name
      ENABLE_REDIS_STOP       = tostring(var.enable_redis_stop)
    }
  }

  tags = { Name = "${local.name_prefix}-env-manager" }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_logs]
}

# ── Lambda Function URL (manual HTTP trigger — no API Gateway needed) ────────
# Auth: AWS_IAM — only principals with lambda:InvokeFunctionUrl can call it.
# Use AWS CLI, AWS SDK, or curl with SigV4 signing.

resource "aws_lambda_function_url" "env_manager" {
  function_name      = aws_lambda_function.env_manager.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST", "GET"]
    allow_headers     = ["content-type", "x-amz-date", "authorization", "x-api-key", "x-amz-security-token"]
    max_age           = 300
  }
}

# ── EventBridge Scheduler permission to invoke Lambda ────────────────────────

resource "aws_lambda_permission" "allow_eventbridge_stop" {
  statement_id  = "AllowEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.env_manager.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.stop.arn
}

resource "aws_lambda_permission" "allow_eventbridge_start" {
  statement_id  = "AllowEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.env_manager.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.start.arn
}

# ── CloudWatch Log Group for Lambda ──────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_env_manager" {
  name              = "/aws/lambda/${aws_lambda_function.env_manager.function_name}"
  retention_in_days = 14

  tags = { Name = "${local.name_prefix}-lambda-logs" }
}
