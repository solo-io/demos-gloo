#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../../common_scripts.sh"
source "${SCRIPT_DIR}/../../working_environment.sh"

if [[ "${K8S_TOOL}" == "kind" ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

POLICY_K8S_CONFIGMAP='allow-get-users'

cleanup_port_forward_deployment 'gateway-proxy-v2'

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  configmap/"${POLICY_K8S_CONFIGMAP}"

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"
