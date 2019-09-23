#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

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
  --filename="$SCRIPT_DIR/../resources/petstore.yaml"

kubectl --namespace='gloo-system' delete virtualservice/default

kubectl --namespace='default' delete \
  --filename="$SCRIPT_DIR/../resources/petclinic-db.yaml" \
  --filename="$SCRIPT_DIR/../resources/petclinic.yaml" \
  --filename="$SCRIPT_DIR/../resources/petclinic-vets.yaml"
