output "lambda_function_arn" {
  description = "ARN of the start/stop Lambda (used by toggle-env workflow)"
  value       = aws_lambda_function.toggle.arn
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}
