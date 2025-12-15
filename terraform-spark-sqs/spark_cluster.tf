# ============================================================================
# Spark Cluster Module - Master + 2 Workers
# ============================================================================

# ============================================================================
# IAM Role for Spark Cluster
# ============================================================================

resource "aws_iam_role" "spark" {
  name = "${var.project_name}-spark-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "spark" {
  name = "${var.project_name}-spark-policy"
  role = aws_iam_role.spark.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_logs.arn,
          "${aws_s3_bucket.raw_logs.arn}/*",
          aws_s3_bucket.spark_scripts.arn,
          "${aws_s3_bucket.spark_scripts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.error_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.raw_files.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "spark" {
  name = "${var.project_name}-spark-profile"
  role = aws_iam_role.spark.name
}

# ============================================================================
# Security Groups
# ============================================================================

resource "aws_security_group" "spark_master" {
  name        = "${var.project_name}-spark-master-sg"
  description = "Security group for Spark Master"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Spark Master Web UI
  ingress {
    description = "Spark Master Web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Spark Master port (from workers)
  ingress {
    description = "Spark Master"
    from_port   = 7077
    to_port     = 7077
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Spark REST API
  ingress {
    description = "Spark REST API"
    from_port   = 6066
    to_port     = 6066
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Spark Master Security Group"
  }
}

resource "aws_security_group" "spark_worker" {
  name        = "${var.project_name}-spark-worker-sg"
  description = "Security group for Spark Workers"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  # Spark Worker Web UI
  ingress {
    description = "Spark Worker Web UI"
    from_port   = 8081
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Worker communication ports
  ingress {
    description = "Worker communication"
    from_port   = 7000
    to_port     = 7999
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Executor ports
  ingress {
    description = "Executor ports"
    from_port   = 8000
    to_port     = 8999
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Spark Worker Security Group"
  }
}

# ============================================================================
# Spark Master
# ============================================================================

resource "aws_instance" "spark_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.spark_master.id]
  iam_instance_profile   = aws_iam_instance_profile.spark.name
  key_name               = var.ssh_key_name

  user_data = base64encode(templatefile("${path.module}/user_data/spark_master.sh", {
    sqs_queue_url     = aws_sqs_queue.raw_files.url
    db_secret_arn     = aws_secretsmanager_secret.db_password.arn
    error_bucket      = aws_s3_bucket.error_logs.bucket
    spark_script_url  = "s3://${aws_s3_bucket.spark_scripts.bucket}/jobs/process_akamai_logs.py"
    aws_region        = var.aws_region
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-spark-master"
    Role = "SparkMaster"
  }
}

# ============================================================================
# Spark Workers
# ============================================================================

resource "aws_instance" "spark_worker" {
  count                  = 2
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.spark_worker.id]
  iam_instance_profile   = aws_iam_instance_profile.spark.name
  key_name               = var.ssh_key_name

  user_data = base64encode(templatefile("${path.module}/user_data/spark_worker.sh", {
    spark_master_ip = aws_instance.spark_master.private_ip
    worker_id       = count.index + 1
    aws_region      = var.aws_region
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-spark-worker-${count.index + 1}"
    Role = "SparkWorker"
  }

  depends_on = [aws_instance.spark_master]
}

# ============================================================================
# Grafana
# ============================================================================

resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana-sg"
  description = "Security group for Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana Web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Grafana Security Group"
  }
}

resource "aws_iam_role" "grafana" {
  name = "${var.project_name}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "grafana" {
  name = "${var.project_name}-grafana-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "grafana" {
  name = "${var.project_name}-grafana-profile"
  role = aws_iam_role.grafana.name
}

resource "aws_instance" "grafana" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.grafana.id]
  iam_instance_profile   = aws_iam_instance_profile.grafana.name
  key_name               = var.ssh_key_name

  user_data = base64encode(templatefile("${path.module}/user_data/grafana.sh", {
    db_secret_arn = aws_secretsmanager_secret.db_password.arn
    aws_region    = var.aws_region
    admin_email   = var.grafana_admin_email
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-grafana"
    Role = "Monitoring"
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "s3_raw_logs_bucket" {
  description = "S3 bucket for Akamai raw logs"
  value       = aws_s3_bucket.raw_logs.bucket
}

output "s3_spark_scripts_bucket" {
  description = "S3 bucket for Spark scripts"
  value       = aws_s3_bucket.spark_scripts.bucket
}

output "sqs_queue_url" {
  description = "SQS queue URL for raw files"
  value       = aws_sqs_queue.raw_files.url
}

output "spark_master_ip" {
  description = "Spark Master public IP"
  value       = aws_instance.spark_master.public_ip
}

output "spark_master_private_ip" {
  description = "Spark Master private IP"
  value       = aws_instance.spark_master.private_ip
}

output "spark_worker_ips" {
  description = "Spark Worker public IPs"
  value       = aws_instance.spark_worker[*].public_ip
}

output "spark_master_url" {
  description = "Spark Master Web UI URL"
  value       = "http://${aws_instance.spark_master.public_ip}:8080"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_secret_arn" {
  description = "ARN of RDS password secret"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://${aws_instance.grafana.public_ip}:3000"
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    spark_master = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.spark_master.public_ip}"
    spark_worker_1 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.spark_worker[0].public_ip}"
    spark_worker_2 = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.spark_worker[1].public_ip}"
    grafana = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_instance.grafana.public_ip}"
  }
}

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    architecture      = "S3 → Lambda → SQS → Spark Cluster → RDS → Grafana"
    s3_raw_bucket     = aws_s3_bucket.raw_logs.bucket
    sqs_queue         = aws_sqs_queue.raw_files.name
    spark_master      = "http://${aws_instance.spark_master.public_ip}:8080"
    spark_workers     = length(aws_instance.spark_worker)
    rds_endpoint      = aws_db_instance.main.endpoint
    grafana_url       = "http://${aws_instance.grafana.public_ip}:3000"
    estimated_cost    = "$114/month"
    files_per_day     = "96 (1 file every 15 min)"
    processing_window = "Poll SQS every 5 minutes (10 files/batch)"
  }
}

