#!/bin/bash

# Before using this script, you should log in to your AWS account
# using the AWS CLI. For example, aws login --profile <aws-profile>.

set -euo pipefail

# Fill your aws profile here
export AWS_PROFILE=

ACCT=$(aws sts get-caller-identity --query Account --output text)

# Fill your region here
REGION=
REGISTRY="$ACCT.dkr.ecr.$REGION.amazonaws.com"
TMP_DOCKER_CONFIG=$(mktemp -d)

# Fill your app name and tag here. It should be the
# same value you use in the node-api manifest
APP=

terraform apply -auto-approve

BASTION_IP=$(terraform output -json bastion_ip | jq -r '.[0]')

for i in {1..5}; do
    if ssh -q ubuntu@$BASTION_IP "test -f /etc/rancher/k3s/k3s.yaml" 2>/dev/null; then
        ssh ubuntu@$BASTION_IP "sudo cat /etc/rancher/k3s/k3s.yaml" > k3s.yaml
        break
    fi
    sleep 5
done   

ssh ubuntu@$BASTION_IP 'sudo cat /etc/rancher/k3s/k3s.yaml' > k3s.yaml

URL=https://$BASTION_IP:6443 yq -i '.clusters[].cluster.server = strenv(URL)' k3s.yaml

export KUBECONFIG=~/sre-capstone/k3s.yaml

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

aws ecr get-login-password --region "$REGION" \
  | docker --config "$TMP_DOCKER_CONFIG" login --username AWS --password-stdin "$REGISTRY"

kubectl create secret generic ecr-cred --from-file=.dockerconfigjson="$TMP_DOCKER_CONFIG/config.json" \
  --type=kubernetes.io/dockerconfigjson

docker buildx build --platform linux/amd64,linux/arm64 -t "$REGISTRY/$APP" --push ./app

kubectl apply -f ./k8s -R

rm -r $TMP_DOCKER_CONFIG

echo "Lab successfully set up!"
