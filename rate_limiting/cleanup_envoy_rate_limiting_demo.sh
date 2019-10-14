#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/../working_environment.sh"

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

PROXY_PID_FILE="${SCRIPT_DIR}/proxy_pf.pid"
if [[ -f "${PROXY_PID_FILE}" ]]; then
  xargs kill <"${PROXY_PID_FILE}" && true # ignore errors
  rm "${PROXY_PID_FILE}"
fi

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

kubectl --namespace='gloo-system' patch settings/default \
  --type='json' \
  --patch='[
    {
      "op": "remove",
      "path": "/spec/extensions/configs/envoy-rate-limit"
    }
  ]'

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"
