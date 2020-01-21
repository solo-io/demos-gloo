#!/usr/bin/env bash
# shellcheck disable=SC2034

K8S_TOOL='minikube' # kind, minikube, k3d, minishift, gke, eks, aks, custom
GLOO_MODE='ent'     # oss, ent, knative, none

GLOO_NAMESPACE='gloo-system'

if [[ "${GLOO_MODE}" == "ent" ]]; then
  # Gloo Enterprise Version
  GLOO_VERSION='1.3.0-beta1'
else
  # Gloo Open Source Version
  GLOO_VERSION='1.3.1'
fi

GLOO_DEMO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Create absolute path reference to top level directory of this demo repo
# GLOO_DEMO_RESOURCES_HOME='https://raw.githubusercontent.com/solo-io/demos-gloo/master/resources'
GLOO_DEMO_RESOURCES_HOME=${GLOO_DEMO_RESOURCES_HOME:-"${GLOO_DEMO_HOME}/resources"}

if [[ "${K8S_TOOL}" == 'k3d' ]]; then
  KUBECONFIG=$(k3d get-kubeconfig --name="${DEMO_CLUSTER_NAME:-k3s-default}")
  export KUBECONFIG
fi
