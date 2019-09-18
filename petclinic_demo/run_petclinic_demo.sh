#!/usr/bin/env bash

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

# Install petclinic application
kubectl --namespace='default' apply \
  --filename "$SCRIPT_DIR/../resources/petclinic-db.yaml" \
  --filename "$SCRIPT_DIR/../resources/petclinic.yaml" \
  --filename "$SCRIPT_DIR/../resources/petclinic-vets.yaml"

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

# Install petstore app to show OpenAPI
kubectl --namespace='default' apply \
  --filename "$SCRIPT_DIR/../resources/petstore.yaml"

# Configure AWS upstreams
if [ -f ~/scripts/secret/aws_credentials.sh ]; then
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

# Expose and open in browser GlooE Web UI Console
WEB_UI_PORT=9088
API_SERVER_PID_FILE=$SCRIPT_DIR/api_server_pf.pid
if [[ -f $API_SERVER_PID_FILE ]]; then
  xargs kill <"$API_SERVER_PID_FILE" && true # ignore errors
  rm "$API_SERVER_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/api-server --watch=true
( (kubectl --namespace='gloo-system' port-forward deployment/api-server ${WEB_UI_PORT:-9088}:8080 >/dev/null) & echo $! > "$API_SERVER_PID_FILE" & )

open "http://localhost:${WEB_UI_PORT:-9088}/"

# Open in browser petclinic home page
PROXY_PORT=9080
PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch=true
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 ${PROXY_PORT:-9080}:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch=true

open "http://localhost:${PROXY_PORT:-9080}/"
