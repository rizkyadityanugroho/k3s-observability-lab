locals {
  common_ingress_rules = {
    ssh            = { from_port = 22, to_port = 22, protocol = "tcp", description = "ssh" }
    http           = { from_port = 80, to_port = 80, protocol = "tcp", description = "http" }
    https          = { from_port = 443, to_port = 443, protocol = "tcp", description = "https" }
    k8s_api        = { from_port = 6443, to_port = 6443, protocol = "tcp", description = "k8s api" }
    kubelet        = { from_port = 10250, to_port = 10250, protocol = "tcp", description = "kubelet" }
    flannel_vxlan  = { from_port = 8472, to_port = 8472, protocol = "udp", description = "flannel vxlan" }
    nodeport_range = { from_port = 30000, to_port = 32767, protocol = "tcp", description = "k8s nodeport range" }
    self_flannel   = { from_port = 8472, to_port = 8472, protocol = "udp", description = "Self Flannel VXLAN", self = true }
  }
}
