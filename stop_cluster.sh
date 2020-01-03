#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/common_scripts.sh"
source "${SCRIPT_DIR}/working_environment.sh"

K8S_TOOL="${K8S_TOOL:-kind}"

case "${K8S_TOOL}" in
  kind)
    kind delete cluster --name="${DEMO_CLUSTER_NAME:-kind}"
    ;;

  minikube)
    minikube delete --profile="${DEMO_CLUSTER_NAME:-minikube}"
    ;;

  k3d)
    unset KUBECONFIG

    k3d delete --name="${DEMO_CLUSTER_NAME:-k3s-default}"
    ;;

  minishift)
    minishift delete --profile="${DEMO_CLUSTER_NAME:-minishift}" --force
    ;;

  gke)
    gcloud container clusters delete "$(whoami)-${DEMO_CLUSTER_NAME:-gke-gloo}" --quiet
    ;;

  eks)
    eksctl delete cluster --name="$(whoami)-${DEMO_CLUSTER_NAME:-eks-gloo}"
    ;;

  # aks)
  #   DEMO_CLUSTER_NAME="$(whoami)-${DEMO_CLUSTER_NAME:-aks-gloo}"
  #   RESOURCE_GROUP_NAME="${DEMO_CLUSTER_NAME}-resource-group"

  #   az aks delete \
  #     --name "${DEMO_CLUSTER_NAME}" \
  #     --resource-group "${RESOURCE_GROUP_NAME}"

  #   az group delete --name "${RESOURCE_GROUP_NAME}"
  #   ;;

  custom) ;;

esac
