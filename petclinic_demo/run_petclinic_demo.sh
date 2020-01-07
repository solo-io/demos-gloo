#!/usr/bin/env bash

PROXY_PORT='8080'
WEB_UI_PORT='9088'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup previous example runs
kubectl --namespace="${GLOO_NAMESPACE}" delete \
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

kubectl --namespace='default' label service/petstore \
  --overwrite='true' \
  'discovery.solo.io/function_discovery=enabled'

# Configure AWS upstream
if [[ -f "${HOME}/scripts/secret/aws_function_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl --namespace="${GLOO_NAMESPACE}" delete \
    --ignore-not-found='true' \
    secret/aws \
    upstream/aws

  # AWS_ACCESS_KEY='<access key>'
  # AWS_SECRET_KEY='<secret key>'
  source "${HOME}/scripts/secret/aws_function_credentials.sh"

  # glooctl create secret aws --name='aws' \
  #   --namespace="${GLOO_NAMESPACE}" \
  #   --access-key="${AWS_ACCESS_KEY}" \
  #   --secret-key="${AWS_SECRET_KEY}"

  kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: aws
  namespace: "${GLOO_NAMESPACE}"
type: Opaque
data:
  aws_access_key_id: $(base64 --wrap='0' <(echo -n "${AWS_ACCESS_KEY}"))
  aws_secret_access_key: $(base64 --wrap='0' <(echo -n "${AWS_SECRET_KEY}"))
EOF

  # glooctl create upstream aws \
  #   --name='aws' \
  #   --namespace="${GLOO_NAMESPACE}" \
  #   --aws-region='us-east-1' \
  #   --aws-secret-name='aws' \
  #   --aws-secret-namespace="${GLOO_NAMESPACE}"

  kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: aws
  namespace: "${GLOO_NAMESPACE}"
spec:
  aws:
    region: us-east-1
    secret_ref:
      name: aws
      namespace: "${GLOO_NAMESPACE}"
EOF
fi # Configure AWS upstream

#
# Configure Traffic Routing rules
#

# glooctl create virtualservice \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}"

# glooctl add route \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}" \
#   --path-prefix='/' \
#   --dest-name='default-petclinic-8080' \
#   --dest-namespace="${GLOO_NAMESPACE}"

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: "${GLOO_NAMESPACE}"
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: "${GLOO_NAMESPACE}"
EOF

#
# Enable localhost access to cluster and open web brower clients
#

# Expose and open in browser GlooE Web UI Console
port_forward_deployment "${GLOO_NAMESPACE}" 'api-server' "${WEB_UI_PORT}:8080"

open "http://localhost:${WEB_UI_PORT}/"

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' "${PROXY_PORT}:8080"

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

open "http://localhost:${PROXY_PORT}/"

# Create localhost port-forward of Gloo installed Promethesu
port_forward_deployment "${GLOO_NAMESPACE}" 'glooe-prometheus-server' '9090'

open 'http://localhost:9090'

# Create localhost port-forward of Gloo installed Grafana
port_forward_deployment "${GLOO_NAMESPACE}" 'glooe-grafana' '3000'

open 'http://localhost:3000'
