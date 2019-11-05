#!/usr/bin/env bash
# shellcheck disable=SC2034

FUNCTION_SECRET_NAME='my-function-secret'
FUNCTION_UPSTREAM_NAME='my-function-upstream'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

if [[ "${K8S_TOOL}" == "kind" ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

cleanup_port_forward_deployment 'gateway-proxy-v2'

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${FUNCTION_SECRET_NAME}" \
  upstream/"${FUNCTION_UPSTREAM_NAME}"
