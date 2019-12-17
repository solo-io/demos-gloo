#!/usr/bin/env bash
#
# Uninstalls Gloo based on settings in working_environment.sh

# Expects
# brew install kubernetes-cli helm

# Optional
# brew install kind minikube skaffold openshift-cli; brew cask install minishift

GLOO_NAMESPACE="${GLOO_NAMESPACE:-gloo-system}"

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/common_scripts.sh"
source "${SCRIPT_DIR}/working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

GLOO_MODE="${GLOO_MODE:-ent}" # oss, ent, knative, none

case "${GLOO_MODE}" in
  ent)
    helm uninstall glooe \
      --namespace="${GLOO_NAMESPACE}"

    kubectl delete namespace "${GLOO_NAMESPACE}" \
      --ignore-not-found='true'
    ;;

  oss)
    helm uninstall gloo \
      --namespace="${GLOO_NAMESPACE}"

    kubectl delete namespace "${GLOO_NAMESPACE}" \
      --ignore-not-found='true'
    ;;

  knative)
    helm uninstall gloo \
      --namespace="${GLOO_NAMESPACE}"

    kubectl delete namespace "${GLOO_NAMESPACE}" \
      --ignore-not-found='true'
    ;;

  none) ;;

esac
