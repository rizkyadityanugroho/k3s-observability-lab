## Architecture:

```mermaid
flowchart LR
    client[Client<br/>k6 load generator<br/>laptop]

    subgraph aws["AWS"]
        igw[Internet gateway]
        subgraph vpc["VPC"]
            subgraph subnet["Public subnet · one AZ"]
                obs["Observability node"<br/>────────────<br/>t4g.medium · k3s SERVER<br/>Prometheus · Loki · Tempo · Grafana · OTel]
                api0["API worker 0"<br/>────────────<br/>t4g.micro · k3s agent<br/>NodeJS service]
                api1["API worker 1"<br/>────────────<br/>t4g.micro · k3s agent<br/>NodeJS service]
                db["Data node"<br/>────────────<br/>t4g.small · k3s agent<br/>PostgreSQL + pgBouncer]
            end
        end
    end

    client -->|HTTP 80/443| igw

    igw --> obs
    igw --> api0
    igw --> api1

    obs -->|"6443 · kubelet/API"| api0
    obs -->|"6443 · kubelet/API"| api1
    obs -->|"6443 · kubelet/API"| db

    obs -.->|"scrape: 9090 metrics"| api0
    obs -.->|"scrape: 9090 metrics"| api1
    obs -.->|"scrape: 9090 metrics"| db

    api0 <-->|"8472 · Flannel VXLAN"| api1
    api0 <-->|"8472 · Flannel VXLAN"| db
    api1 <-->|"8472 · Flannel VXLAN"| db

    api0 -->|"6432 · pgBouncer"| db
    api1 -->|"6432 · pgBouncer"| db

    style obs fill:#e5dbff,stroke:#6741d9
    style api0 fill:#d3f9d8,stroke:#2b8a3e
    style api1 fill:#d3f9d8,stroke:#2b8a3e
    style db fill:#ffe8cc,stroke:#e67700
```

## Resources setup:
- AWS VPC
  - 1 public subnet, 1 AZ
  - ap-southeast-3 region
- Backend
  - S3 Bucket: tf-state-sre-capstone
- AWS EC2 Node:
  - 1x `obs-node`
    - t4g.medium
    - taint: obs-control
    - SG Ingress:
      - 22 From x IP
      - 6443 (k8s API) from `worker-node` and `db-node`
      - 4317 (OTLP) from `worker-node` and `db-node`
      - 4318 (OTLP) from `worker-node` and `db-node`
      - 3000 (Grafana) From x IP
      - 8472 (Flannel VXLAN) from `self`, `worker-node` and `db-node`
  - 2x `worker-node`
    - t4g.micro
    - SG Ingress:
      - 10250 (kubelet) from `obs-node`
      - 8472 (Flannel VXLAN) from `self`, `worker-node` and `db-node`
      - 3000 (NodeJS API) from `worker-node`
  - 1x `db-node`
    - t4g.small
    - SG Ingress:
      - 10250 (kubelet) from `obs-node`
      - 8472 (Flannel VXLAN) from `self`, `worker-node` and `db-node`
      - 6432 (pgBouncer) from `worker-node`
