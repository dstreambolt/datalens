variable "project_name" {}
variable "ami_id" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "mysql_host" {}
variable "mysql_password" {}
variable "kafka_broker" {}
variable "iam_instance_profile" {}
variable "alb_target_group_arn" {}

resource "aws_instance" "ingest" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data_replace_on_change = true

  user_data = templatefile("${path.root}/user_data/ingest.sh", {
    mysql_host     = var.mysql_host
    mysql_password = var.mysql_password
    kafka_broker   = var.kafka_broker
  })

  tags = { Name = "${var.project_name}-ingest" }
}

resource "aws_lb_target_group_attachment" "ingest" {
  target_group_arn = var.alb_target_group_arn
  target_id        = aws_instance.ingest.id
  port             = 5000
}

output "public_ip" {
  value = aws_instance.ingest.public_ip
}

output "private_ip" {
  value = aws_instance.ingest.private_ip
}

