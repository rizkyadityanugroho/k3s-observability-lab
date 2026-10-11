data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip = "${chomp(data.http.my_ip.response_body)}/32"
}

module "sg-obs-node" {
  source = "./modules/sg"
  name   = "sg_obs-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    ssh           = { cidr_blocks = [local.my_ip] }
    k8s_api       = { cidr_blocks = [local.my_ip] }
    flannel_vxlan = { source_security_group_id = module.sg-worker-node.id }
    self_flannel  = {}
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from db-node"
      name                     = "sg-obs-db-flannel"
      protocol                 = "udp"
      source_security_group_id = module.sg-db-node.id
    },
    {
      from_port   = 3000
      to_port     = 3000
      description = "Grafana Web"
      name        = "grafana-web"
      protocol    = "tcp"
      cidr_blocks = [local.my_ip]
    },
    {
      from_port                = 6443
      to_port                  = 6443
      protocol                 = "tcp"
      description              = "k8s API from workers"
      source_security_group_id = module.sg-worker-node.id
    },
    {
      from_port                = 6443
      to_port                  = 6443
      protocol                 = "tcp"
      description              = "k8s API from dbmodule.ec2_obs"
      source_security_group_id = module.sg-db-node.id
    }
  ]
}

module "sg-worker-node" {
  source = "./modules/sg"
  name   = "sg_worker-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    kubelet       = { source_security_group_id = module.sg-obs-node.id }
    flannel_vxlan = { source_security_group_id = module.sg-obs-node.id }
    self_flannel  = {}
    ssh           = { source_security_group_id = module.sg-obs-node.id }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from db-node"
      protocol                 = "udp"
      name                     = "sg-worker-db-flannel"
      source_security_group_id = module.sg-db-node.id
    }
  ]
}

module "sg-db-node" {
  source = "./modules/sg"
  name   = "sg_db-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    kubelet       = { source_security_group_id = module.sg-obs-node.id }
    flannel_vxlan = { source_security_group_id = module.sg-obs-node.id }
    self_flannel  = {}
    ssh           = { source_security_group_id = module.sg-obs-node.id }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from worker-node"
      protocol                 = "udp"
      name                     = "sg-db-worker-flannel"
      source_security_group_id = module.sg-worker-node.id
    }
  ]
}
