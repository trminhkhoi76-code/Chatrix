locals {
  function_name = "${var.project}-${var.environment}-toggle-env"
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<-EOF
      import boto3, os, json

      def handler(event, context):
          action = event.get("action", "status")
          ec2 = boto3.client("ec2")
          rds = boto3.client("rds")
          instance_id = os.environ["EC2_INSTANCE_ID"]
          db_id = os.environ["RDS_INSTANCE_ID"]

          if action == "start":
              ec2.start_instances(InstanceIds=[instance_id])
              rds.start_db_instance(DBInstanceIdentifier=db_id)
          elif action == "stop":
              ec2.stop_instances(InstanceIds=[instance_id])
              rds.stop_db_instance(DBInstanceIdentifier=db_id)

          return {"statusCode": 200, "body": json.dumps({"action": action})}
    EOF
    filename = "handler.py"
  }
}

resource "aws_iam_role" "lambda" {
  name = "${var.project}-${var.environment}-scheduler-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.project}-${var.environment}-scheduler-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["rds:StartDBInstance", "rds:StopDBInstance", "rds:DescribeDBInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "toggle" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      EC2_INSTANCE_ID = var.ec2_instance_id
      RDS_INSTANCE_ID = var.rds_instance_id
    }
  }

  tags = { Name = local.function_name }
}

resource "aws_iam_role" "scheduler" {
  name = "${var.project}-${var.environment}-eventbridge-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project}-${var.environment}-eventbridge-scheduler-policy"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.toggle.arn
    }]
  })
}

resource "aws_scheduler_schedule" "start" {
  count = var.enable_schedule ? 1 : 0
  name  = "${var.project}-${var.environment}-start"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = var.start_schedule
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.toggle.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "start" })
  }
}

resource "aws_scheduler_schedule" "stop" {
  count = var.enable_schedule ? 1 : 0
  name  = "${var.project}-${var.environment}-stop"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = var.stop_schedule
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.toggle.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "stop" })
  }
}
