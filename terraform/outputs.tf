# ================================================================
# SQS Outputs
# ================================================================
output "notifications_queue_url" {
  description = "URL of the test SQS queue used to exercise the terraform plan/apply and IAM auto-attach workflow"
  value       = aws_sqs_queue.notifications.url
}

output "notifications_queue_arn" {
  description = "ARN of the test SQS queue"
  value       = aws_sqs_queue.notifications.arn
}
