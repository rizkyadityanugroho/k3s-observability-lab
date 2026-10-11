output "ec2_ip" {
  value = aws_instance.ec2[*].public_ip
}

output "ec2_dns" {
  value = aws_instance.ec2[*].public_dns
}

output "private_ip" {
  value = aws_instance.ec2[*].private_ip
}
