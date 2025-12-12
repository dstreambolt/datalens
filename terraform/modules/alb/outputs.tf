output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "ingest_target_group_arn" {
  description = "ARN of the ingest target group"
  value       = aws_lb_target_group.ingest.arn
}

output "mtls_trust_store_bucket" {
  description = "S3 bucket name for mTLS trust store (upload CA certificates here)"
  value       = aws_s3_bucket.mtls_trust_store.bucket
}

output "mtls_trust_store_arn" {
  description = "ARN of the mTLS trust store"
  value       = aws_lb_trust_store.mtls.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (with mTLS)"
  value       = aws_lb_listener.https.arn
}

