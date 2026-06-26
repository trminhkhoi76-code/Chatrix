output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "api_target_group_arn" {
  value = aws_lb_target_group.api.arn
}

output "security_group_id" {
  value = aws_security_group.alb.id
}

output "http_listener_arn" {
  description = "HTTP listener ARN — passed to alb-target-group module for listener rules"
  value       = aws_lb_listener.http.arn
}
