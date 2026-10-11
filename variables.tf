variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "vpc_name" {
  type        = string
  description = "Name tag for the VPC"
}

variable "vpc_az_count" {

  type        = number
  description = "Number of availability zones to spread subnets across"
}

variable "vpc_host_bits" {
  type        = number
  description = "Host bits for subnet CIDR calculation"
}

variable "key_pair_path" {
  type        = string
  description = "SSH public key"
}
