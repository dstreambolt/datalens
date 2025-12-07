variable "project_name" {}
variable "ami_id" {}
variable "key_name" {}
variable "subnet_id" {}
variable "security_group_id" {}
variable "iam_instance_profile" {}

resource "aws_instance" "kafka" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = file("${path.root}/user_data/kafka.sh")
  user_data_replace_on_change = true

  tags = { Name = "${var.project_name}-kafka" }
}

output "private_ip" {
  value = aws_instance.kafka.private_ip
}

