#!/usr/bin/env bash

KEYCLOAK_NAMESPACE='keycloak'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

helm uninstall keycloak \
  --namespace="${KEYCLOAK_NAMESPACE}"

kubectl --namespace="${KEYCLOAK_NAMESPACE}" delete \
  --ignore-not-found='true' \
  secret/realm-secret

kubectl delete namespace "${KEYCLOAK_NAMESPACE}" \
  --ignore-not-found='true'
