# DStreamBolt Production Infrastructure - Main Configuration
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "project_name" {
  description = "Project name"
  type        = string
  default     = "dstreambolt"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# ==========================================
# NETWORKING MODULE
# ==========================================
module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  aws_region   = var.aws_region
}

# ==========================================
# ALB MODULE
# ==========================================
module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  alb_security_group = module.networking.alb_security_group_id
}

# ==========================================
# DEVOPS MODULE (Deploy first - provides MySQL)
# ==========================================
module "devops" {
  source = "./modules/devops"

  project_name         = var.project_name
  ami_id               = data.aws_ami.ubuntu.id
  key_name             = var.key_name
  subnet_id            = module.networking.public_subnet_ids[0]
  security_group_id    = module.networking.devops_security_group_id
  mysql_root_password  = var.mysql_root_password
  iam_instance_profile = module.networking.ec2_instance_profile_name
}

# ==========================================
# KAFKA MODULE (Private subnet)
# ==========================================
module "kafka" {
  source = "./modules/kafka"

  project_name         = var.project_name
  ami_id               = data.aws_ami.ubuntu.id
  key_name             = var.key_name
  subnet_id            = module.networking.private_subnet_ids[0]
  security_group_id    = module.networking.kafka_security_group_id
  iam_instance_profile = module.networking.ec2_instance_profile_name
}

# ==========================================
# INGEST MODULE (Ingestion)
# ==========================================
module "ingest" {
  source = "./modules/ingest"

  project_name         = var.project_name
  ami_id               = data.aws_ami.ubuntu.id
  key_name             = var.key_name
  subnet_id            = module.networking.public_subnet_ids[0]
  security_group_id    = module.networking.ingest_security_group_id
  mysql_host           = module.devops.private_ip
  mysql_password       = var.mysql_root_password
  kafka_broker         = "${module.kafka.private_ip}:9092"
  iam_instance_profile = module.networking.ec2_instance_profile_name
  alb_target_group_arn = module.alb.ingest_target_group_arn
}

# ==========================================
# COMPUTE MODULE (Spark)
# ==========================================
module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  ami_id               = data.aws_ami.ubuntu.id
  key_name             = var.key_name
  subnet_id            = module.networking.public_subnet_ids[0]
  security_group_id    = module.networking.compute_security_group_id
  kafka_broker         = "${module.kafka.private_ip}:9092"
  iam_instance_profile = module.networking.ec2_instance_profile_name
}

# ==========================================
# LANDING PAGE MODULE
# ==========================================
module "landing_page" {
  source = "./modules/landing-page"

  alb_dns_name = module.alb.alb_dns_name
  ingest_ip    = module.ingest.public_ip
  kafka_ip     = module.kafka.private_ip
  compute_ip   = module.compute.public_ip
  devops_ip    = module.devops.public_ip
}

data "aws_caller_identity" "current" {}

# ==========================================
# OUTPUTS
# ==========================================
output "alb_url" {
  description = "Application Load Balancer URL"
  value       = "https://${module.alb.alb_dns_name}"
}

output "landing_page_url" {
  description = "Landing Page URL"
  value       = "https://${module.alb.alb_dns_name}/"
}

output "ingestion_api_url" {
  description = "Ingestion API endpoint"
  value       = "https://${module.alb.alb_dns_name}/ingest"
}

output "service_endpoints" {
  description = "All service endpoints accessible via ALB"
  value = {
    landing_page  = "https://${module.alb.alb_dns_name}/"
    ingestion_api = "https://${module.alb.alb_dns_name}/ingest"
    health_check  = "https://${module.alb.alb_dns_name}/health"
    jenkins       = "https://${module.alb.alb_dns_name}/jenkins"
    grafana       = "https://${module.alb.alb_dns_name}/grafana"
    kafka_manager = "https://${module.alb.alb_dns_name}/kafkamgr"
    spark_ui      = "https://${module.alb.alb_dns_name}/spark"
  }
}

output "direct_access" {
  description = "Direct access to instances"
  value = {
    ingest_ip  = module.ingest.public_ip
    compute_ip = module.compute.public_ip
    devops_ip  = module.devops.public_ip
    kafka_ip   = module.kafka.private_ip
  }
}

output "credentials" {
  description = "Service credentials"
  value = {
    mysql_password   = var.mysql_root_password
    grafana_login    = "admin / DStreamBolt2025!"
    jenkins_password = "Check: ssh ubuntu@${module.devops.public_ip} 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"
  }
  sensitive = true
}

output "summary" {
  description = "Deployment Summary"
  sensitive   = true
  value       = <<-EOT

  ╔════════════════════════════════════════════════════════════════╗
  ║         🚀 DStreamBolt Infrastructure Deployed!                ║
  ╚════════════════════════════════════════════════════════════════╝

  📊 LANDING PAGE (Beautiful UI):
     https://${module.alb.alb_dns_name}/

  📥 INGESTION API:
     Endpoint: https://${module.alb.alb_dns_name}/ingest
     Health:   https://${module.alb.alb_dns_name}/health
     Method:   POST (gzipped JSON)

  🛠️  DEVOPS TOOLS (via ALB):
     Jenkins:        https://${module.alb.alb_dns_name}/jenkins
     Grafana:        https://${module.alb.alb_dns_name}/grafana
     Kafka Manager:  https://${module.alb.alb_dns_name}/kafkamgr
     Spark UI:       https://${module.alb.alb_dns_name}/spark

  💻 DIRECT ACCESS:
     Ingest:  ssh -i ~/dstreambolt-access-key.pem ubuntu@${module.ingest.public_ip}
     Compute: ssh -i ~/dstreambolt-access-key.pem ubuntu@${module.compute.public_ip}
     DevOps:  ssh -i ~/dstreambolt-access-key.pem ubuntu@${module.devops.public_ip}

  🔐 CREDENTIALS:
     MySQL:   root / ${var.mysql_root_password}
     Grafana: admin / DStreamBolt2025!
     Jenkins: Check /var/lib/jenkins/secrets/initialAdminPassword

  💰 ESTIMATED MONTHLY COST: ~$102/month (~$55 with free tier)

  ✅ All services are production-ready!

  EOT
}

