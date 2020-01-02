#!/usr/bin/env bash
# shellcheck disable=SC2034

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

cleanup_port_forward_deployment 'gateway-proxy'
cleanup_port_forward_deployment 'ingress-proxy'

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  routetable/a-routes \
  routetable/b-routes \
  routetable/b2-routes

  kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  ingress/petstore-ingress

  kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"
