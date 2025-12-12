variable "project_name" {}
variable "ami_id" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "kafka_broker" {}
variable "iam_instance_profile" {}

# Spark Master Instance
resource "aws_instance" "spark_master" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data_replace_on_change = true

  user_data = templatefile("${path.root}/user_data/spark_master.sh", {
    project_name = var.project_name
  })

  tags = {
    Name = "${var.project_name}-spark-master"
    Role = "spark-master"
  }
}

# Spark Executor Instance
resource "aws_instance" "spark_executor" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data_replace_on_change = true

  user_data = templatefile("${path.root}/user_data/spark_executor.sh", {
    spark_master_ip = aws_instance.spark_master.private_ip
  })

  depends_on = [aws_instance.spark_master]

  tags = {
    Name = "${var.project_name}-spark-executor"
    Role = "spark-executor"
  }
}

# Outputs
output "master_public_ip" {
  value = aws_instance.spark_master.public_ip
}

output "master_private_ip" {
  value = aws_instance.spark_master.private_ip
}

output "executor_public_ip" {
  value = aws_instance.spark_executor.public_ip
}

output "executor_private_ip" {
  value = aws_instance.spark_executor.private_ip
}

# Backward compatibility outputs
output "public_ip" {
  value       = aws_instance.spark_master.public_ip
  description = "Deprecated: Use master_public_ip instead"
}

output "private_ip" {
  value       = aws_instance.spark_master.private_ip
  description = "Deprecated: Use master_private_ip instead"
}

