data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "ec2" {
  count                  = var.ec2_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ec2_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = var.sg_id
  key_name               = var.ssh_key_name
  tags                   = { Name = "${var.ec2_name}-${count.index + 1}" }
  user_data              = var.user_data
}


