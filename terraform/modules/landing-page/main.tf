variable "alb_dns_name" {}
variable "ingest_ip" {}
variable "kafka_ip" {}
variable "compute_ip" {}
variable "devops_ip" {}

output "landing_page_url" {
  value = "https://${var.alb_dns_name}/"
}

output "info" {
  value = "Landing page served by ALB with service endpoints"
}

