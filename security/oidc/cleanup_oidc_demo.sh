#!/usr/bin/env bash

OIDC_PROVIDER=${OIDC_PROVIDER:-dex} # dex, google, sfdc

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../../common_scripts.sh"
source "${SCRIPT_DIR}/../../working_environment.sh"

K8S_SECRET_NAME='my-oauth-secret'

cleanup_port_forward_deployment 'gateway-proxy-v2'

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${K8S_SECRET_NAME}"

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml"

if [[ "${OIDC_PROVIDER}" == 'dex' ]]; then
  cleanup_port_forward_deployment 'dex'

  helm delete --purge dex
fi
