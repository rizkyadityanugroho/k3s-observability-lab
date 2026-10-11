variable "ec2_type" {
  type        = string
  description = "EC2 Instance Type"
  default     = "t4g.micro"
}

variable "ssh_key_name" {
  type        = string
  description = "SSH Key Name"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet ID"
}

variable "sg_id" {
  type        = list(string)
  description = "List of security group IDs used by EC2"
}

variable "ec2_name" {
  type        = string
  description = "EC2 name"
}

variable "ec2_count" {
  type        = number
  description = "Number of EC2"
  default     = 1
}

variable "user_data" {
  type        = string
  description = "User data to be executed"
  default     = null
}
