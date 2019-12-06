#!/usr/bin/env bash

# Based on https://docs.solo.io/gloo/latest/gloo_routing/hello_world/

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

# Install and wait for petstore example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# glooctl add route \
#   --path-prefix='/sample-route-1' \
#   --dest-name='default-petstore-8080' \
#   --prefix-rewrite='/api/pets'

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
      - prefix: /sample-route-1
      routeAction:
        single:
          upstream:
            name: default-petstore-8080
            namespace: gloo-system
      routeOptions:
        prefixRewrite: /api/pets
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould work\n"
curl "${PROXY_URL}/sample-route-1"

printf "\n\nShould fail with 404\n"
curl --write-out '%{http_code}' "${PROXY_URL}/api/pets"
