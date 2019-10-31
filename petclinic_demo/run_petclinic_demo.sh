#!/usr/bin/env bash

PROXY_PORT=9080
WEB_UI_PORT=9088

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

#
# Install example services and external upstreams
#

# Install petclinic application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-vets.yaml"

# Install petstore app to show OpenAPI
kubectl --namespace='default' apply \
  --filename "${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Configure AWS upstreams
if [[ -f "${HOME}/scripts/secret/aws_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl --namespace='gloo-system' delete \
    --ignore-not-found='true' \
    secret/aws \
    upstream/aws

  # glooctl create secret aws --name 'aws' --namespace 'gloo-system' --access-key '<access key>' --secret-key '<secret key>'
  source "${HOME}/scripts/secret/aws_credentials.sh"

  kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: aws
  namespace: gloo-system
spec:
  upstreamSpec:
    aws:
      region: us-east-1
      secretRef:
        name: aws
        namespace: gloo-system
EOF
fi

#
# Configure Traffic Routing rules
#

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system'

# glooctl add route \
#   --name='default' \
#   --path-prefix='/' \
#   --dest-name='default-petclinic-8080' \
#   --dest-namespace='gloo-system'

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: gloo-system
EOF

#
# Enable localhost access to cluster and open web brower clients
#

# Expose and open in browser GlooE Web UI Console
port_forward_deployment 'gloo-system' 'api-server' "${WEB_UI_PORT:-9088}:8080"

open "http://localhost:${WEB_UI_PORT:-9088}/"

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' "${PROXY_PORT:-9080}:8080"

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

open "http://localhost:${PROXY_PORT:-9080}/"
