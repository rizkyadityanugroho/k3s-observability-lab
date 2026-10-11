resource "aws_security_group" "this" {
  name        = var.name
  description = "Managed by Terraform: ${var.name}"
  vpc_id      = var.vpc_id
  tags        = { Name = var.name }
}

locals {
  expanded_common_rules = {
    for key, cfg in var.common_ingress :
    key => merge(local.common_ingress_rules[key], cfg)
  }

  all_ingress_rules = merge(
    local.expanded_common_rules,
    { for idx, r in var.custom_ingress : "custom-${idx}" => r }
  )

  all_egress_rules = { for idx, r in var.custom_egress : idx => r }
}

output "id" {
  value       = aws_security_group.this.id
  description = "Security group ID"
}

resource "aws_security_group_rule" "ingress" {
  for_each = local.all_ingress_rules

  type                     = "ingress"
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  source_security_group_id = each.value.source_security_group_id
  self                     = try(each.value.self, null)
  description              = each.value.description
  security_group_id        = aws_security_group.this.id
}

resource "aws_security_group_rule" "egress" {
  for_each = local.all_egress_rules

  type              = "egress"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = each.value.cidr_blocks
  description       = each.value.description
  security_group_id = aws_security_group.this.id
}
