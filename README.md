# k3s Observability Lab on AWS

A small, reproducible AWS lab that runs an instrumented Node.js API on k3s and routes **metrics, logs, and traces** through Grafana Alloy into Prometheus, Loki, and Tempo. Grafana is provisioned with its data sources and dashboard from Kubernetes manifests.

This is deliberately a learning environment rather than a production Kubernetes platform. The point is to exercise the whole operational path:

```text
request → Node.js API → OpenTelemetry → Alloy → Prometheus / Loki / Tempo → Grafana
```

## What it demonstrates

- Terraform modules for a VPC, role-specific security groups, EC2 instances, and ECR.
- k3s bootstrap using EC2 user data: one server plus labelled agent nodes.
- An ARM64 (`t4g`) container path from local image build to Amazon ECR to k3s.
- Node.js OpenTelemetry instrumentation for all three signals:
  - traces via OTLP/gRPC;
  - application request counter and duration histogram metrics;
  - Pino logs bridged into the OpenTelemetry Logs SDK.
- Grafana Alloy as the in-cluster OTLP gateway.
- Prometheus remote-write ingestion, Loki log ingestion, and Tempo trace ingestion.
- Grafana provisioning for data sources, Loki↔Tempo trace/log correlation, and a v2 dashboard-as-code resource.
- PromQL-based availability, error ratio, error-budget burn rate, request rate, and latency percentile panels.

## Architecture

```mermaid
flowchart LR
    client["Laptop / k6"]

    subgraph aws["AWS · ap-southeast-3"]
        subgraph vpc["One public subnet · one AZ"]
            obs["obs-node\nk3s server + control plane\nAlloy · Prometheus · Loki · Tempo · Grafana"]
            api0["worker 0\nk3s agent\nnode-api"]
            api1["worker 1\nk3s agent\nnode-api"]
            db["db-node\nk3s agent\nreserved role"]
        end
    end

    client -->|HTTP 80 via Traefik / ServiceLB| obs
    client -->|Grafana NodePort 30000| obs
    client -->|kubectl / SSH| obs
    obs -->|Service → Pod overlay| api0
    obs -->|Service → Pod overlay| api1

    api0 -->|OTLP gRPC 4317| obs
    api1 -->|OTLP gRPC 4317| obs
    obs -->|Alloy routes signals| plgt["Prometheus · Loki · Tempo"]
    plgt --> grafana["Grafana"]

    obs <-->|6443 · 10250 · UDP 8472| api0
    obs <-->|6443 · 10250 · UDP 8472| api1
    obs <-->|6443 · 10250 · UDP 8472| db
    api0 <-->|UDP 8472| api1
    api0 <-->|UDP 8472| db
    api1 <-->|UDP 8472| db
```

### Node roles

| Role | Current instance type | k3s role | Label | Workloads |
|---|---:|---|---|---|
| `obs-node` | `t4g.small` | server/control plane | `role=obs` | Alloy, Prometheus, Loki, Tempo, Grafana |
| `workers-node-1..2` | `t4g.micro` | agent | `role=worker` | `node-api` |
| `db-node` | `t4g.small` | agent | `role=db` | Reserved for the database layer |

The observability components have `nodeSelector: { role: obs }`; the API has `nodeSelector: { role: worker }`.

> **Known topology limitation:** the `obs-node` currently combines the k3s server and the full observability stack. This is intentionally cheap, but it means resource pressure can take out both the control plane and the monitoring stack. The next sensible improvement is a dedicated `role=o11y` agent node and moving Alloy/Prometheus/Loki/Tempo/Grafana there.

## Repository layout

```text
.
├── app/                    # Instrumented Express + Pino API and Dockerfile
├── k8s/                    # Workload, ConfigMap, datasource, and dashboard manifests
├── modules/
│   ├── ec2/                # ARM Ubuntu EC2 module
│   ├── sg/                 # Reusable security-group rule presets
│   └── vpc/                # VPC, subnet, route-table wiring
├── architecture.md         # Detailed infrastructure notes and SG matrix
├── ec2.tf                  # k3s server/agent bootstrap user data
├── security_groups.tf      # Role-specific AWS security groups
└── main.tf                 # Terraform backend, provider, VPC, and ECR
```

## Prerequisites

- Terraform `>= 1.5`
- AWS credentials with VPC, EC2, ECR, and S3-state access
- An existing SSH public key
- `aws`, `kubectl`, `docker`, and `git`
- A region that supports ARM Ubuntu and `t4g` instances; this lab uses `ap-southeast-3`

## Infrastructure setup

### 1. Configure Terraform inputs

Terraform state is configured for the S3 bucket `tf-state-sre-capstone`; it must already exist and be accessible before `terraform init`.

Create `terraform.tfvars` locally (it is intentionally ignored):

```hcl
vpc_cidr      = "192.168.10.0/24"
vpc_az_count  = 2
vpc_host_bits = 1
vpc_name      = "sre-vpc"
key_pair_path = "~/.ssh/id_ed25519.pub"
```

These are the current values in [`terraform.tfvars.example`](terraform.tfvars.example). Do not put a private key, AWS credentials, or account ID in Git.

### 2. Provision AWS resources and configure kubectl

Set `AWS_PROFILE` only if your local AWS CLI needs a named profile. Do not commit profile names, account IDs, or credentials.

```bash
# Optional: export AWS_PROFILE=<your-local-profile>
terraform init
terraform fmt -recursive
terraform validate
terraform apply -auto-approve

# bastion_ip is a one-element output list, hence the jq index.
BASTION_IP="$(terraform output -json bastion_ip | jq -r '.[0]')"

# Bootstrap takes longer than Terraform resource creation. Wait for the k3s API,
# rather than relying on a fixed sleep alone.
until ssh "ubuntu@$BASTION_IP" 'sudo test -s /etc/rancher/k3s/k3s.yaml'; do
  sleep 5
done

ssh "ubuntu@$BASTION_IP" 'sudo cat /etc/rancher/k3s/k3s.yaml' > k3s.yaml
URL="https://$BASTION_IP:6443" yq -i '.clusters[].cluster.server = strenv(URL)' k3s.yaml
export KUBECONFIG="$PWD/k3s.yaml"

kubectl get nodes -o wide
kubectl get pods -A -o wide
```

Terraform creates the VPC/subnet, ECR repository, security groups, and EC2 instances. The server bootstrap starts k3s with `role=obs`; the agents join it with `role=worker` or `role=db`. `k3s.yaml` is ignored by Git because it contains cluster credentials.

Expected node roles:

```text
role=obs      # k3s server/control plane
role=worker   # two API workers
role=db       # reserved database node
```

## Build and deploy the API

### 1. Build and push a multi-architecture image

The cluster is ARM64. The local deployment helper builds a multi-architecture image so the same tag works for ARM64 k3s nodes and an AMD64 development machine:

```bash
export AWS_REGION=ap-southeast-3
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
export IMAGE_TAG=0.0.1

# Authenticate Docker for the push.
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag "$ECR_REGISTRY/node-api:$IMAGE_TAG" \
  --push \
  ./app
```

Create or refresh the ECR pull secret. The temporary Docker config holds only the short-lived ECR token and avoids overwriting your normal Docker login config. ECR authorization tokens expire, so rerun this when pods fail with an expired-token error:

```bash
TMP_DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$TMP_DOCKER_CONFIG"' EXIT

aws ecr get-login-password --region "$AWS_REGION" \
  | docker --config "$TMP_DOCKER_CONFIG" login \
      --username AWS --password-stdin "$ECR_REGISTRY"

kubectl create secret generic ecr-cred \
  --from-file=.dockerconfigjson="$TMP_DOCKER_CONFIG/config.json" \
  --type=kubernetes.io/dockerconfigjson \
  --dry-run=client -o yaml | kubectl apply -f -

rm -rf "$TMP_DOCKER_CONFIG"
trap - EXIT
```

### 2. Set the image reference

Edit `k8s/node-api.yaml` and replace:

```yaml
image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/node-api:<TAG>
```

with the image you pushed (for example, `$ECR_REGISTRY/node-api:$IMAGE_TAG`). Then apply the complete manifest directory. The repository file names deliberately put the ConfigMaps before the workloads that mount them:

```bash
kubectl apply -f ./k8s
kubectl get deploy,po,svc,ingress -o wide
```

The Ingress host is `node-api.local`. From a client that can reach a node’s port 80, send the Host header:

```bash
curl -i -H 'Host: node-api.local' http://<NODE_PUBLIC_IP>/
curl -i -H 'Host: node-api.local' http://<NODE_PUBLIC_IP>/slow
curl -i -H 'Host: node-api.local' http://<NODE_PUBLIC_IP>/error
```

`/slow` waits about two seconds; `/error` returns HTTP 500. They exist to generate recognizable latency and error telemetry.

## Deploy the observability stack

`kubectl apply -f ./k8s` in the preceding API deployment step also deploys Alloy, Prometheus, Loki, Tempo, Grafana, their ConfigMaps/PVCs, Grafana data sources, and the v2 dashboard. Check that the components landed on the obs node:

```bash
kubectl get pods -o wide
```

Grafana is exposed with NodePort `30000`:

```text
http://<OBS_NODE_PUBLIC_IP>:30000
```

The project provisions three Grafana datasources:

| Datasource | Cluster URL | Purpose |
|---|---|---|
| Prometheus | `http://prom:9090` | Metrics, SLI, SLO and latency queries |
| Loki | `http://loki:3100` | Structured application logs |
| Tempo | `http://tempo:3200` | Distributed traces |

It also provisions the exported Grafana v2 dashboard from `k8s/grafana-v2-dashboard.yaml`.

## Telemetry pipeline

```text
node-api
  ├── traces ─┐
  ├── metrics ├── OTLP/gRPC :4317 → Alloy → Tempo / Prometheus / Loki
  └── logs   ─┘

Grafana
  ├── Prometheus: rates, errors, histogram quantiles
  ├── Loki: Pino JSON logs and trace-id lookup
  └── Tempo: trace waterfall and trace-to-logs links
```

The API is started with its instrumentation module preloaded:

```dockerfile
CMD ["node", "--require", "./instrumentation.js", "index.js"]
```

That preload order matters: Pino must be instrumented before `pino-http` is imported. The Logs SDK and `PinoInstrumentation` bridge Pino records to OTLP while preserving JSON logs on stdout.

## Verification checklist

Generate some normal, slow, and failing traffic first:

```bash
for path in / /slow /error; do
  curl -sS -o /dev/null -H 'Host: node-api.local' \
    -w "%{http_code} $path\n" \
    "http://<NODE_PUBLIC_IP>$path"
done
```

Then verify each boundary instead of assuming an open Grafana page proves ingestion:

```bash
# Kubernetes placement and health
kubectl get pods -o wide
kubectl get pods -l app=node-api

# API logs should include Pino JSON, trace context, slow/error messages
kubectl logs deploy/node-api --tail=100

# Alloy receives and exports signals
kubectl logs deploy/alloy --tail=100

# Kubernetes resource metrics; requires k3s metrics-server to scrape kubelets
kubectl top nodes
kubectl top pods
```

In Grafana:

1. **Prometheus** — query `app_http_server_requests_total` and `app_http_server_duration_seconds_bucket`.
2. **Loki** — start with `{service_name="node-api"} | json`; find `Slow response` or `Intentional error`.
3. **Tempo** — search `service.name = node-api` and open a trace.
4. From a Loki event with a `traceid`, use **View Trace**; from Tempo, use **Trace to logs**.
5. Open the provisioned dashboard for availability, error ratio, burn rate, request rate, and p90/p95/p99 latency.

Useful PromQL examples:

```promql
# 5-minute availability: 1 - 5xx ratio
1 - (
  sum(rate(app_http_server_requests_total{http_response_status_code=~"5.."}[5m]))
  /
  sum(rate(app_http_server_requests_total[5m]))
)
```

```promql
# p95 latency in seconds
histogram_quantile(
  0.95,
  sum by (le) (rate(app_http_server_duration_seconds_bucket[5m]))
)
```

```promql
# Mean latency in seconds
sum(rate(app_http_server_duration_seconds_sum[5m]))
/
sum(rate(app_http_server_duration_seconds_count[5m]))
```

## Security-group model

The security-group design is role based:

- the control plane accepts operator SSH/API access from the detected caller IP;
- workers and DB node accept kubelet traffic from the obs node;
- k3s/Flannel nodes permit UDP/8472 VXLAN traffic across their role groups;
- workers join the k3s API at TCP/6443;
- Grafana is exposed as NodePort TCP/30000 only to the detected caller IP.

Read [`architecture.md`](architecture.md) for the full current SG matrix and traffic diagram.

A useful distinction while debugging:

```text
Flannel VXLAN (UDP/8472) moves pod-overlay traffic.
metrics-server scrapes node kubelets on node-IP TCP/10250.
```

They are separate network paths. If `kubectl top nodes` has `<unknown>` for only some nodes, check which node runs metrics-server and whether its security group can reach every target node’s TCP/10250.

## Known limitations and intentional trade-offs

- Single AZ, public subnet, and one k3s server; no HA or control-plane failover.
- `obs-node` shares the control plane with the observability stack; separate it before treating the lab as resilient.
- The k3s installer currently fetches the newest release during bootstrap. Pin `INSTALL_K3S_VERSION` to a tested release for fully repeatable rebuilds.
- `user_data` only runs on first boot. Replace an instance when testing changed bootstrap logic:

  ```bash
  terraform apply -replace='module.ec2_obs.aws_instance.ec2[0]'
  ```

- The generated k3s join token appears in Terraform state and instance user data. Fine for a short-lived lab; use SSM Parameter Store or Secrets Manager in a real environment.
- Prometheus, Loki, Tempo, and Grafana use local-path storage. There is no backup, replication, or durable remote storage.
- `prom-data` is declared but is not yet mounted by `k8s/prometheus.yaml`; Prometheus samples are therefore currently ephemeral. Mount it at `/prometheus` before relying on retained metrics.
- Grafana’s dashboard ConfigMap embeds an exported JSON document. It works, but extracting the dashboard to a standalone file and generating the ConfigMap with Kustomize would make diffs much easier to review.
- The AWS region, backend bucket, AMI selection, and node sizes are currently project-specific rather than parameterized.

## Teardown

This project creates billable AWS resources. When finished:

```bash
terraform destroy
```

Then verify in AWS that no EC2 instances, EBS volumes, ECR images, security groups, or other resources from the lab were left behind.

## Next improvements

1. Add a dedicated `role=o11y` agent node and move the observability stack off the control plane.
2. Mount `prom-data` into Prometheus and set retention explicitly.
3. Pin k3s to a tested version rather than resolving GitHub `latest` at boot.
4. Move the dashboard JSON out of the ConfigMap literal; generate the ConfigMap from source.
5. Add health/readiness probes and resource requests/limits to all workloads.
6. Add recording rules and multi-window burn-rate alerts after the SLI has enough traffic.
7. Add the PostgreSQL + pgBouncer workload on `role=db`, plus a traceable API database call.

## License

No license has been declared yet.
