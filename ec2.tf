resource "aws_key_pair" "main" {
  key_name   = "ssh-key"
  public_key = file(var.key_pair_path)
}

resource "random_password" "k3s_token" {
  length      = 15
  special     = false
  min_lower   = 1
  min_numeric = 1
  min_upper   = 1
}

module "ec2_control" {
  source       = "./modules/ec2"
  ec2_type     = "t4g.small"
  subnet_ids   = module.vpc.public_subnet_ids
  ec2_name     = "control-node"
  ssh_key_name = aws_key_pair.main.key_name
  sg_id        = [module.sg-control-node.id]
  user_data    = <<-EOF
  #!/bin/bash
  set -euxo pipefail
  exec > >(tee -a /var/log/user-data.log) 2>&1

  TOKEN="$(curl -s -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 600" http://169.254.169.254/latest/api/token)"
  PUBLIC_HOSTNAME="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-hostname)"
  PUBLIC_IPV4="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)"
  PRIVATE_IPV4="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)"
    
  apt-get update -y
  apt-get upgrade -y
  curl -sfL https://get.k3s.io\
  | K3S_TOKEN=${random_password.k3s_token.result} \
  INSTALL_K3S_VERSION=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name') \
  sh -s - server \
  --tls-san "$PUBLIC_HOSTNAME" \
  --tls-san "$PUBLIC_IPV4" \
  --tls-san "$PRIVATE_IPV4" \
  --node-label "role=control"
  EOF
}

module "ec2_obs" {
  source       = "./modules/ec2"
  ec2_type     = "t4g.small"
  subnet_ids   = module.vpc.public_subnet_ids
  ec2_name     = "obs-node"
  ssh_key_name = aws_key_pair.main.key_name
  sg_id        = [module.sg-obs-node.id]
  user_data    = <<-EOF
  #!/bin/bash
  set -euxo pipefail
  exec > >(tee -a /var/log/user-data.log) 2>&1

  apt-get update -y
  apt-get upgrade -y
  curl -sfL https://get.k3s.io \
  | INSTALL_K3S_VERSION=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name') \
  K3S_URL=https://${module.ec2_control.private_ip[0]}:6443 \
  K3S_TOKEN=${random_password.k3s_token.result} \
  INSTALL_K3S_EXEC="agent --node-label role=obs" sh -
  EOF
}

module "ec2_workers" {
  source       = "./modules/ec2"
  sg_id        = [module.sg-worker-node.id]
  ec2_name     = "workers-node"
  ec2_count    = 2
  ec2_type     = "t4g.micro"
  ssh_key_name = aws_key_pair.main.key_name
  subnet_ids   = module.vpc.public_subnet_ids
  user_data    = <<-EOF
  #!/bin/bash
  set -euxo pipefail
  exec > >(tee -a /var/log/user-data.log) 2>&1 

  apt-get update -y
  apt-get upgrade -y
  curl -sfL https://get.k3s.io \
  | INSTALL_K3S_VERSION=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name') \
  K3S_URL=https://${module.ec2_control.private_ip[0]}:6443 \
  K3S_TOKEN=${random_password.k3s_token.result} \
  INSTALL_K3S_EXEC="agent --node-label role=worker" sh -
  EOF
}

module "ec2_db" {
  source       = "./modules/ec2"
  subnet_ids   = module.vpc.public_subnet_ids
  sg_id        = [module.sg-db-node.id]
  ec2_type     = "t4g.small"
  ssh_key_name = aws_key_pair.main.key_name
  ec2_name     = "db-node"
  user_data    = <<-EOF
  #!/bin/bash
  set -euxo pipefail
  exec > >(tee -a /var/log/user-data.log) 2>&1
   
  apt-get update -y
  apt-get upgrade -y
  curl -sfL https://get.k3s.io \
  | INSTALL_K3S_VERSION=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name') \
  K3S_URL=https://${module.ec2_control.private_ip[0]}:6443 \
  K3S_TOKEN=${random_password.k3s_token.result} \
  INSTALL_K3S_EXEC="agent --node-label role=db" sh -
  EOF
}

output "bastion_ip" {
  value = module.ec2_control.ec2_ip
}
