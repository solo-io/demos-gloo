#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/common_scripts.sh"
source "${SCRIPT_DIR}/working_environment.sh"

K8S_TOOL="${K8S_TOOL:-kind}"

case "${K8S_TOOL}" in
  kind)
    unset KUBECONFIG

    kind delete cluster --name="${DEMO_CLUSTER_NAME:-kind}"
    ;;

  minikube)
    minikube delete --profile="${DEMO_CLUSTER_NAME:-minikube}"
    ;;

  minishift)
    minishift delete --profile="${DEMO_CLUSTER_NAME:-minishift}" --force
    ;;

  gcloud)
    gcloud container clusters delete "$(whoami)-${DEMO_CLUSTER_NAME:-gke-gloo}" --quiet
    ;;

  custom) ;;

esac
