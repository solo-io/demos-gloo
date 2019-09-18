#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

K8S_SECRET_NAME='my-oauth-secret'
POLICY_K8S_CONFIGMAP='allow-jwt'

kubectl --namespace=gloo-system delete virtualservice/default
kubectl --namespace=gloo-system delete secret/"$K8S_SECRET_NAME"
kubectl --namespace=gloo-system delete configmap/"$POLICY_K8S_CONFIGMAP"

kubectl --namespace=default delete \
  --filename "$SCRIPT_DIR/../resources/petclinic-db.yaml" \
  --filename "$SCRIPT_DIR/../resources/petclinic.yaml"

DEX_PID_FILE=$SCRIPT_DIR/dex_pf.pid
if [[ -f $DEX_PID_FILE ]]; then
  xargs kill <"$DEX_PID_FILE" && true # ignore errors
  rm "$DEX_PID_FILE"
fi

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi

helm delete --purge dex
