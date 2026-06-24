# ---------------------------------------------------------------------------
# Application Load Balancer
#
# Path routing:
#   /ws/chat*  → chatrix-websocket (port 8081, WebSocket upgrade preserved)
#   /*         → chatrix-api       (port 8080, REST)
#
# TLS is optional: if acm_certificate_arn is set, HTTP redirects to HTTPS.
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Access logs to S3 would cost ~$0.50/GB — disabled for cost savings
  # Enable when debugging traffic issues:
  # access_logs { bucket = "..." enabled = true }

  tags = { Name = "${local.name_prefix}-alb" }
}

# ---------------------------------------------------------------------------
# Target Group — REST API (port 8080)
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "api" {
  name     = "${local.name_prefix}-api"
  port     = var.app_api_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name_prefix}-api-tg" }
}

resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.app.id
  port             = var.app_api_port
}

# ---------------------------------------------------------------------------
# Target Group — WebSocket (port 8081)
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "websocket" {
  name     = "${local.name_prefix}-ws"
  port     = var.app_ws_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Sticky sessions keep a user's WebSocket on the same backend instance
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  # Netty's WsServerProtocolHandler returns 400 on plain HTTP requests
  # (no Upgrade header) — this is the expected response for ALB health checks
  health_check {
    enabled             = true
    path                = "/ws/chat"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "400"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name_prefix}-ws-tg" }
}

resource "aws_lb_target_group_attachment" "websocket" {
  target_group_arn = aws_lb_target_group.websocket.arn
  target_id        = aws_instance.app.id
  port             = var.app_ws_port
}

# ---------------------------------------------------------------------------
# Listeners — no TLS  (plain HTTP, used when acm_certificate_arn == "")
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "http_plain" {
  count = var.acm_certificate_arn == "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = { Name = "${local.name_prefix}-http-listener" }
}

resource "aws_lb_listener_rule" "ws_plain" {
  count = var.acm_certificate_arn == "" ? 1 : 0

  listener_arn = aws_lb_listener.http_plain[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket.arn
  }

  condition {
    path_pattern { values = ["/ws/*"] }
  }
}

# ---------------------------------------------------------------------------
# Listeners — with TLS  (HTTP redirects to HTTPS)
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "http_redirect" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = { Name = "${local.name_prefix}-http-redirect" }
}

resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = { Name = "${local.name_prefix}-https-listener" }
}

resource "aws_lb_listener_rule" "ws_https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.websocket.arn
  }

  condition {
    path_pattern { values = ["/ws/*"] }
  }
}
