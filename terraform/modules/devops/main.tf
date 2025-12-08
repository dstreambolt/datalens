variable "project_name" {}
variable "ami_id" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "mysql_root_password" {}
variable "iam_instance_profile" {}

resource "aws_instance" "devops" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data_replace_on_change = true
  user_data                   = file("${path.root}/user_data/devops.sh")

  tags = { Name = "${var.project_name}-devops" }

  lifecycle {
    ignore_changes = [user_data, user_data_replace_on_change]
  }
}

output "public_ip" {
  value = aws_instance.devops.public_ip
}

output "private_ip" {
  value = aws_instance.devops.private_ip
}

