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

kubectl --namespace='default' label service/petstore \
  --overwrite='true' \
  'discovery.solo.io/function_discovery=enabled'

# Configure AWS upstream
if [[ -f "${HOME}/scripts/secret/aws_function_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl --namespace='gloo-system' delete \
    --ignore-not-found='true' \
    secret/aws \
    upstream/aws

  # AWS_ACCESS_KEY='<access key>'
  # AWS_SECRET_KEY='<secret key>'
  source "${HOME}/scripts/secret/aws_function_credentials.sh"

  # glooctl create secret aws --name='aws' \
  #   --namespace='gloo-system' \
  #   --access-key="${AWS_ACCESS_KEY}" \
  #   --secret-key="${AWS_SECRET_KEY}"

  kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: aws
  namespace: gloo-system
type: Opaque
data:
  aws_access_key_id: $(echo -n "${AWS_ACCESS_KEY}" | base64 --wrap='0' -)
  aws_secret_access_key: $(echo -n "${AWS_SECRET_KEY}" | base64 --wrap='0' -)
EOF

  # glooctl create upstream aws \
  #   --name='aws' \
  #   --namespace='gloo-system' \
  #   --aws-region='us-east-1' \
  #   --aws-secret-name='aws' \
  #   --aws-secret-namespace='gloo-system'

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
fi # Configure AWS upstream

#
# Configure Traffic Routing rules
#

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system'

# glooctl add route \
#   --name='default' \
#   --namespace='gloo-system' \
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
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: gloo-system
EOF

# Enable Function Discovery for all Upstreams
kubectl --namespace='gloo-system' patch settings/default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  discovery:
    fdsMode: BLACKLIST
EOF
)"

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
