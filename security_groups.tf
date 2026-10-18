data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip = "${chomp(data.http.my_ip.response_body)}/32"
}

module "sg-control-node" {
  source = "./modules/sg"
  name   = "sg_control-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    ssh           = { cidr_blocks = [local.my_ip] }
    k8s_api       = { cidr_blocks = [local.my_ip] }
    self_flannel  = {}
    flannel_vxlan = { source_security_group_id = module.sg-obs-node.id }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      protocol                 = "udp"
      description              = "Flannel VXLAN from worker-node"
      source_security_group_id = module.sg-worker-node.id
    },
    {
      from_port                = 8472
      to_port                  = 8472
      protocol                 = "udp"
      description              = "Flannel VXLAN from db-node"
      source_security_group_id = module.sg-db-node.id
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
      description              = "k8s API from db"
      source_security_group_id = module.sg-db-node.id
    },
    {
      from_port                = 6443
      to_port                  = 6443
      protocol                 = "tcp"
      description              = "k8s API from obs"
      source_security_group_id = module.sg-obs-node.id
    }
  ]
}

module "sg-obs-node" {
  source = "./modules/sg"
  name   = "sg_obs-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    flannel_vxlan = { source_security_group_id = module.sg-worker-node.id }
    self_flannel  = {}
    kubelet       = { source_security_group_id = module.sg-control-node.id }
    ssh           = { source_security_group_id = module.sg-control-node.id }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from control-node"
      protocol                 = "udp"
      source_security_group_id = module.sg-control-node.id
    },
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from db-node"
      protocol                 = "udp"
      source_security_group_id = module.sg-db-node.id
    },
    {
      from_port   = 30000
      to_port     = 30000
      description = "Grafana Web"
      protocol    = "tcp"
      cidr_blocks = [local.my_ip]
    },
  ]
}

module "sg-worker-node" {
  source = "./modules/sg"
  name   = "sg_worker-node"
  vpc_id = module.vpc.vpc_id

  common_ingress = {
    kubelet       = { source_security_group_id = module.sg-control-node.id }
    flannel_vxlan = { source_security_group_id = module.sg-obs-node.id }
    self_flannel  = {}
    ssh           = { source_security_group_id = module.sg-control-node.id }
    http          = { cidr_blocks = [local.my_ip] }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from control-node"
      protocol                 = "udp"
      source_security_group_id = module.sg-control-node.id
      }, {
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
    kubelet       = { source_security_group_id = module.sg-control-node.id }
    flannel_vxlan = { source_security_group_id = module.sg-obs-node.id }
    self_flannel  = {}
    ssh           = { source_security_group_id = module.sg-control-node.id }
  }

  custom_ingress = [
    {
      from_port                = 8472
      to_port                  = 8472
      description              = "Flannel VXLAN from control-node"
      protocol                 = "udp"
      source_security_group_id = module.sg-control-node.id
    },
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
