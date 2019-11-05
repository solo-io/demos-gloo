#!/usr/bin/env bash

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
        regex: '/[a-z]{5}'
      directResponseAction:
        status: 200
        body: "Matched"
    - matcher:
        prefix: /
      directResponseAction:
        status: 200
        body: "Fail"
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould work\n"
curl "${PROXY_URL}/posts"

printf "\nShould Fail\n"
curl "${PROXY_URL}/foo"
