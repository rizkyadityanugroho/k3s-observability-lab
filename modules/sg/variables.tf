variable "name" {
  type        = string
  description = "Name for the security group"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to create the SG in"
}

variable "common_ingress" {
  description = "Map of common ingress rules\n key: rule name,\nvalue: cidr_blocks/source_sg to attach"
  type = map(object({
    cidr_blocks              = optional(list(string), [])
    source_security_group_id = optional(string, null)
  }))
  default = {}
}

variable "custom_ingress" {
  type = list(object({
    description              = optional(string, "")
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string), [])
    source_security_group_id = optional(string, null)
    self                     = optional(bool, null)
    name                     = optional(string, "")
  }))
  default = []
}

variable "custom_egress" {
  type = list(object({
    description = optional(string, "")
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = optional(list(string), [])
    name        = optional(string, "")
  }))
  default = [{
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all egress"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    name        = "default"
  }]
}
