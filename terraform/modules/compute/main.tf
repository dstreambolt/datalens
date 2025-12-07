variable "project_name" {}
variable "ami_id" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "kafka_broker" {}
variable "iam_instance_profile" {}

resource "aws_instance" "compute" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data_replace_on_change = true
  user_data                   = file("${path.root}/user_data/compute.sh")

  tags = { Name = "${var.project_name}-compute" }
}

output "public_ip" {
  value = aws_instance.compute.public_ip
}

output "private_ip" {
  value = aws_instance.compute.private_ip
}

