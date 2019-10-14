#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/../working_environment.sh"

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

LOGGER_PID_FILE="${SCRIPT_DIR}/logger.pid"
if [[ -f "${LOGGER_PID_FILE}" ]]; then
  xargs kill <"${LOGGER_PID_FILE}" && true # ignore errors
  rm "${LOGGER_PID_FILE}" "${SCRIPT_DIR}/proxy.log"
fi

# Reset Gloo proxy logging to info
kubectl --namespace='gloo-system' port-forward deployment/gateway-proxy-v2 19000:19000 >/dev/null 2>&1 &
PID=$!
# curl localhost:19000/logging?level=info --request POST >/dev/null
http POST localhost:19000/logging level==info >/dev/null
kill "$PID"

PROXY_PID_FILE="${SCRIPT_DIR}/proxy_pf.pid"
if [[ -f "${PROXY_PID_FILE}" ]]; then
  xargs kill <"${PROXY_PID_FILE}" && true # ignore errors
  rm "${PROXY_PID_FILE}"
fi

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"
