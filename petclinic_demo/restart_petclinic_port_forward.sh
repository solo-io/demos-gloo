#!/usr/bin/env bash

PROXY_PORT='9080'
WEB_UI_PORT='9088'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

port_forward_deployment "${GLOO_NAMESPACE}" 'api-server' "${WEB_UI_PORT:-9088}:8080"

port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' "${PROXY_PORT:-9080}:8080"

port_forward_deployment "${GLOO_NAMESPACE}" 'glooe-prometheus-server' '9090'

port_forward_deployment "${GLOO_NAMESPACE}" 'glooe-grafana' '3000'
