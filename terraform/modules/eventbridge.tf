# ---------------------------------------------------------------------------
# EventBridge Scheduler — Auto start/stop schedule (Asia/Tokyo timezone)
#
# Default schedule:
#   START  Mon–Fri  08:00 JST  →  EC2 + RDS start
#   STOP   Mon–Fri  20:00 JST  →  EC2 + RDS stop
#
# Override any time with:
#   aws lambda invoke --function-name <name> --payload '{"action":"override","value":"force_on"}' /dev/null
#   aws lambda invoke --function-name <name> --payload '{"action":"override","value":"force_off"}' /dev/null
#   aws lambda invoke --function-name <name> --payload '{"action":"override","value":"none"}' /dev/null
#
# Cost impact:
#   ┌─────────────────┬──────────────────┬────────────────────────────────┐
#   │ Resource        │ Full month cost  │ Cost @ 8h/day weekdays only    │
#   ├─────────────────┼──────────────────┼────────────────────────────────┤
#   │ EC2 t4g.small   │ ~$12             │ ~$3.3   (saves ~$8.7)          │
#   │ RDS db.t3.micro │ ~$18             │ ~$5.0   (saves ~$13)           │
#   │ Redis (stopped) │ ~$14             │ ~$0     (saves ~$14)  *        │
#   │ ALB             │ ~$18             │ ~$18    (always on)             │
#   ├─────────────────┼──────────────────┼────────────────────────────────┤
#   │ Subtotal saving │ ~$36–50/month    │                                │
#   └─────────────────┴──────────────────┴────────────────────────────────┘
#   * Redis saving only when enable_redis_stop = true
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule_group" "chatrix" {
  name = "${local.name_prefix}-schedules"
  tags = { Name = "${local.name_prefix}-schedule-group" }
}

# ── STOP schedule ─────────────────────────────────────────────────────────────

resource "aws_scheduler_schedule" "stop" {
  name       = "${local.name_prefix}-stop"
  group_name = aws_scheduler_schedule_group.chatrix.name
  description = "Stop Chatrix EC2 + RDS (and optionally Redis) at end of business day"

  # EventBridge Scheduler supports IANA timezone natively
  schedule_expression          = var.schedule_stop_cron
  schedule_expression_timezone = "Asia/Tokyo"

  # Allow up to 5 minutes to start the Lambda if it's briefly busy
  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 5
  }

  state = var.enable_schedule ? "ENABLED" : "DISABLED"

  target {
    arn      = aws_lambda_function.env_manager.arn
    role_arn = aws_iam_role.lambda_env_manager.arn

    input = jsonencode({
      action        = "stop"
      include_redis = var.enable_redis_stop
    })

    retry_policy {
      maximum_attempts       = 2
      maximum_event_age_in_seconds = 300
    }
  }
}

# ── START schedule ────────────────────────────────────────────────────────────

resource "aws_scheduler_schedule" "start" {
  name       = "${local.name_prefix}-start"
  group_name = aws_scheduler_schedule_group.chatrix.name
  description = "Start Chatrix EC2 + RDS (and optionally Redis) at start of business day"

  schedule_expression          = var.schedule_start_cron
  schedule_expression_timezone = "Asia/Tokyo"

  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 5
  }

  state = var.enable_schedule ? "ENABLED" : "DISABLED"

  target {
    arn      = aws_lambda_function.env_manager.arn
    role_arn = aws_iam_role.lambda_env_manager.arn

    input = jsonencode({
      action = "start"
    })

    retry_policy {
      maximum_attempts             = 3
      maximum_event_age_in_seconds = 600
    }
  }
}

# ── RDS 7-day auto-start guard ─────────────────────────────────────────────
# AWS automatically restarts a stopped RDS after 7 days.
# This EventBridge rule catches the auto-start event and re-stops the instance
# if the override is NOT force_on.

resource "aws_cloudwatch_event_rule" "rds_auto_start" {
  name        = "${local.name_prefix}-rds-auto-start-guard"
  description = "Re-stop RDS if AWS auto-started it after 7-day limit (fires during scheduled off-hours)"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      SourceIdentifier = [aws_db_instance.main.identifier]
      EventID          = ["RDS-EVENT-0154"] # "DB instance started"
    }
  })
}

resource "aws_cloudwatch_event_target" "rds_auto_start_lambda" {
  rule      = aws_cloudwatch_event_rule.rds_auto_start.name
  target_id = "RdsAutoStartLambda"
  arn       = aws_lambda_function.env_manager.arn

  # Only re-stop if it's outside business hours — pass a conditional stop
  input = jsonencode({
    action        = "stop"
    include_redis = false
    source        = "rds-auto-start-guard"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_rds_guard" {
  statement_id  = "AllowEventBridgeRdsGuard"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.env_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_auto_start.arn
}
