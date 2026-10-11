variable "cidr" {
  type = string
}

variable "name" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "host_bits" {
  type = number
}
