#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

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
    - matchers:
      - prefix: /a/b
        headers:
        - name: my_header
          value: give_me_x
      directResponseAction:
        status: 200
        body: "Route to X"
    - matchers:
      - prefix: /a/b
        headers:
        - name: my_header
          value: give_me_y
      directResponseAction:
        status: 200
        body: "Route to Y"
    - matchers:
      - prefix: /
      directResponseAction:
        status: 200
        body: "Other"
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould return X\n"
curl --header "my_header: give_me_x" "${PROXY_URL}/a/b/foo"

printf "\nShould return Y\n"
curl --header "my_header: give_me_y" "${PROXY_URL}/a/b/foo"

printf "\nShould return Other\n"
curl "${PROXY_URL}/a/b/foo"
