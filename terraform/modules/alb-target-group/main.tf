resource "aws_lb_target_group" "websocket" {
  name        = "${var.project}-${var.environment}-ws-tg"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    # Netty WS server returns 400 for plain HTTP requests — treat as healthy
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200-400"
  }

  stickiness {
    type    = "lb_cookie"
    enabled = true
  }

  tags = { Name = "${var.project}-${var.environment}-ws-tg" }
}

resource "aws_lb_listener_rule" "websocket" {
  listener_arn = var.listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket.arn
  }

  condition {
    path_pattern {
      values = ["/ws/chat*"]
    }
  }
}
