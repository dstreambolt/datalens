# ============================================================================
# DataLens Pipeline with Spark Cluster - Complete Terraform Configuration
# ============================================================================
# Architecture: S3 → Lambda → SQS → Spark Cluster → RDS PostgreSQL → Grafana
# Cost: $114/month
# Region: sa-east-1 (São Paulo, Brazil - for Mobly)
# ============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "DataLens"
      Customer    = "Mobly"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Analytics"
    }
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region (São Paulo for Mobly)"
  type        = string
  default     = "sa-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "mobly-datalens"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_email" {
  description = "Grafana admin email for alerts"
  type        = string
  default     = "devops@mobly.com.br"
}

variable "your_ip" {
  description = "Your IP for SSH access (CIDR format)"
  type        = string
  default     = "0.0.0.0/0" # Change this to your IP!
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instances"
  type        = string
  default     = "mobly-datalens-key"
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ============================================================================
# VPC & Networking
# ============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "Public"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "Private"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================================================
# S3 Buckets
# ============================================================================

resource "aws_s3_bucket" "raw_logs" {
  bucket = "${var.project_name}-raw-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "Akamai Raw Logs"
    DataType    = "Raw"
    Retention   = "90-days"
    Compression = "gzip"
  }
}

resource "aws_s3_bucket_versioning" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "spark_scripts" {
  bucket = "${var.project_name}-spark-scripts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "Spark Scripts"
  }
}

resource "aws_s3_bucket" "error_logs" {
  bucket = "${var.project_name}-errors-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "Processing Errors"
  }
}

# ============================================================================
# SQS Queue
# ============================================================================

resource "aws_sqs_queue" "raw_files_dlq" {
  name                      = "${var.project_name}-raw-files-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name = "Dead Letter Queue"
  }
}

resource "aws_sqs_queue" "raw_files" {
  name                       = "${var.project_name}-raw-files"
  visibility_timeout_seconds = 900 # 15 minutes
  message_retention_seconds  = 345600 # 4 days
  receive_wait_time_seconds  = 20 # Long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.raw_files_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "Raw Files Queue"
  }
}

resource "aws_sqs_queue_policy" "raw_files" {
  queue_url = aws_sqs_queue.raw_files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.raw_files.arn
      }
    ]
  })
}

# ============================================================================
# Lambda Function
# ============================================================================

resource "aws_iam_role" "lambda_trigger" {
  name = "${var.project_name}-lambda-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_trigger" {
  name = "${var.project_name}-lambda-trigger-policy"
  role = aws_iam_role.lambda_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.raw_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.raw_files.arn
      }
    ]
  })
}

data "archive_file" "lambda_trigger" {
  type        = "zip"
  output_path = "${path.module}/lambda_trigger.zip"

  source {
    content = <<-EOF
import json
import boto3
from datetime import datetime

sqs = boto3.client('sqs')
QUEUE_URL = '${aws_sqs_queue.raw_files.url}'

def lambda_handler(event, context):
    """Triggered by S3 PutObject event. Sends S3 file path to SQS."""
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        size = record['s3']['object']['size']

        if not key.endswith('.csv.gz'):
            print(f"Skipping non-gzip file: {key}")
            continue

        message_body = json.dumps({
            'bucket': bucket,
            'key': key,
            'size': size,
            'timestamp': datetime.utcnow().isoformat()
        })

        response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=message_body
        )

        print(f"Sent to SQS: s3://{bucket}/{key} (MessageId: {response['MessageId']})")

    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(event["Records"])} files')
    }
EOF
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "s3_trigger" {
  filename         = data.archive_file.lambda_trigger.output_path
  function_name    = "${var.project_name}-s3-trigger"
  role             = aws_iam_role.lambda_trigger.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_trigger.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      SQS_QUEUE_URL = aws_sqs_queue.raw_files.url
    }
  }

  tags = {
    Name = "S3 to SQS Trigger"
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw_logs.arn
}

resource "aws_s3_bucket_notification" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv.gz"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ============================================================================
# RDS PostgreSQL
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name_prefix = "${var.project_name}-rds-password-"
  description = "RDS PostgreSQL master password"

  tags = {
    Name = "RDS Master Password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = "mobly"
  })
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "RDS Subnet Group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from Spark"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "PostgreSQL from Grafana"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.grafana.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "mobly"
  username = var.db_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = {
    Name = "Mobly Analytics DB"
  }
}

# ============================================================================
# Spark Cluster (Continue in next file due to length)
# ============================================================================

