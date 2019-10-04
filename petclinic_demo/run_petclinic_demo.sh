#!/usr/bin/env bash

PROXY_PORT=9080
WEB_UI_PORT=9088


# Will exit script if we would use an uninitialised variable:
set -o nounset
# Will exit script when a simple command (not a control structure) fails:
set -o errexit

function print_error {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

if [[ $K8S_TOOL == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  virtualservice/default && true # ignore errors

#
# Install example services and external upstreams
#

# Install petclinic application
kubectl --namespace='default' apply \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic-db.yaml" \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic.yaml" \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic-vets.yaml"

# Install petstore app to show OpenAPI
kubectl --namespace='default' apply \
  --filename "$GLOO_DEMO_RESOURCES_HOME/petstore.yaml"

# Configure AWS upstreams
if [[ -f ~/scripts/secret/aws_credentials.sh ]]; then
  # Cleanup old resources
  kubectl --namespace='gloo-system' delete secret/aws upstream/aws && true # ignore errors

  # glooctl create secret aws --name 'aws' --namespace 'gloo-system' --access-key '<access key>' --secret-key '<secret key>'
  source ~/scripts/secret/aws_credentials.sh

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
API_SERVER_PID_FILE="$SCRIPT_DIR/api_server_pf.pid"
if [[ -f $API_SERVER_PID_FILE ]]; then
  xargs kill <"$API_SERVER_PID_FILE" && true # ignore errors
  rm "$API_SERVER_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/api-server --watch='true'
( (kubectl --namespace='gloo-system' port-forward deployment/api-server ${WEB_UI_PORT:-9088}:8080 >/dev/null) & echo $! > "$API_SERVER_PID_FILE" & )

open "http://localhost:${WEB_UI_PORT:-9088}/"

# Open in browser petclinic home page
PROXY_PID_FILE="$SCRIPT_DIR/proxy_pf.pid"
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
( (kubectl --namespace='gloo-system' port-forward deployment/gateway-proxy-v2 ${PROXY_PORT:-9080}:8080 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

open "http://localhost:${PROXY_PORT:-9080}/"
