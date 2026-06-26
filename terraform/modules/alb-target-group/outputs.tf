output "target_group_arn" {
  description = "WebSocket target group ARN (port 8081)"
  value       = aws_lb_target_group.websocket.arn
}
