#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

if [[ $K8S_TOOL == "kind" ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi

API_SERVER_PID_FILE=$SCRIPT_DIR/api_server_pf.pid
if [[ -f $API_SERVER_PID_FILE ]]; then
  xargs kill <"$API_SERVER_PID_FILE" && true # ignore errors
  rm "$API_SERVER_PID_FILE"
fi

kubectl --namespace='gloo-system' delete \
  upstream/aws \
  secret/aws

kubectl --namespace='default' delete \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petstore.yaml"

kubectl --namespace='gloo-system' delete virtualservice/default

kubectl --namespace='default' delete \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic-db.yaml" \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic.yaml" \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petclinic-vets.yaml"
