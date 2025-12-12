# ALB Module - Application Load Balancer with all listeners

variable "project_name" {}
variable "vpc_id" {}
variable "public_subnet_ids" {}
variable "alb_security_group" {}

# TLS Certificate for HTTPS
resource "tls_private_key" "alb" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = "*.elb.amazonaws.com"
    organization = var.project_name
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group]
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.project_name}-alb" }
}

# Target Groups
resource "aws_lb_target_group" "ingest" {
  name     = "${var.project_name}-ingest-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
}

# HTTP Listener (redirect to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# S3 bucket for mTLS trust store (CA certificates)
resource "aws_s3_bucket" "mtls_trust_store" {
  bucket = "${var.project_name}-mtls-trust-store-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-mtls-trust-store"
  }
}

resource "aws_s3_bucket_versioning" "mtls_trust_store" {
  bucket = aws_s3_bucket.mtls_trust_store.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Upload CA certificate to S3 (will be created separately)
# After generating certs, upload with:
# aws s3 cp certs/ca/ca-cert.pem s3://${bucket_name}/ca-bundle.pem

# Trust store for mTLS
resource "aws_lb_trust_store" "mtls" {
  name = "${var.project_name}-mtls-trust-store"

  ca_certificates_bundle_s3_bucket = aws_s3_bucket.mtls_trust_store.bucket
  ca_certificates_bundle_s3_key    = "ca-bundle.pem"

  # This will fail initially until CA cert is uploaded to S3
  # Upload first, then apply

  tags = {
    Name = "${var.project_name}-mtls-trust-store"
  }
}

# HTTPS Listener with mTLS enabled
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb.arn

  # Enable mTLS
  mutual_authentication {
    mode            = "verify" # Options: "off", "verify", "passthrough"
    trust_store_arn = aws_lb_trust_store.mtls.arn

    # When client cert validation fails, reject the request
    ignore_client_certificate_expiry = false
  }

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      status_code  = "200"
      message_body = file("${path.module}/landing-page-simple.html")
    }
  }
}

# Data source to get account ID
data "aws_caller_identity" "current" {}

# Listener Rules for each service
resource "aws_lb_listener_rule" "ingest" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }

  condition {
    path_pattern {
      values = ["/ingest", "/ingest/*", "/health"]
    }
  }
}

