#!/usr/bin/env bash

# Based on https://docs.solo.io/gloo/latest/gloo_integrations/ingress

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup previous example runs
kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  ingress/petstore-ingress

# Install and wait for petstore example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

kubectl --namespace='default' rollout status deployment/petstore --watch='true'

kubectl apply --filename - <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: petstore-ingress
  annotations:
    # note: this annotation is only required if you've set
    # REQUIRE_INGRESS_CLASS=true in the environment for
    # the ingress deployment
    kubernetes.io/ingress.class: gloo
spec:
  rules:
  - host: gloo.example.com
    http:
      paths:
      - path: /.*
        backend:
          serviceName: petstore
          servicePort: 8080
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'ingress-proxy' '9090:80'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:9090'

printf "\nShould work\n"
curl --header "Host: gloo.example.com" "${PROXY_URL}/api/pets"
