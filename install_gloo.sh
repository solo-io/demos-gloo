#!/usr/bin/env bash
#
# Installs Gloo based on settings in working_environment.sh

# Expects
# brew install kubernetes-cli helm

# Optional
# brew install kind minikube skaffold openshift-cli; brew cask install minishift

GLOO_ENT_VERSION='1.0.0-rc7'
GLOO_OSS_VERSION='1.2.10'

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
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_ENT_VERSION}"

    if [[ -f "${HOME}/scripts/secret/glooe_license_key.sh" ]]; then
      # export GLOOE_LICENSE_KEY=<valid key>
      source "${HOME}/scripts/secret/glooe_license_key.sh"
    fi
    if [[ -z "${GLOOE_LICENSE_KEY}" ]]; then
      echo 'You must set GLOOE_LICENSE_KEY with GlooE activation key'
      exit
    fi

    helm repo add glooe 'http://storage.googleapis.com/gloo-ee-helm'
    helm repo update
    kubectl create namespace "${GLOO_NAMESPACE}" && true # ignore errors
    helm upgrade --install glooe glooe/gloo-ee \
      --namespace="${GLOO_NAMESPACE}" \
      --version="${GLOO_VERSION}" \
      --set="license_key=${GLOOE_LICENSE_KEY}" \
      --set="gloo.gatewayProxies.gatewayProxy.readConfig=true"
    ;;

  oss)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    kubectl create namespace "${GLOO_NAMESPACE}" && true # ignore errors
    helm upgrade --install gloo gloo/gloo \
      --namespace="${GLOO_NAMESPACE}" \
      --version="${GLOO_VERSION}" \
      --set="gatewayProxies.gatewayProxy.readConfig=true"

      # needed for minishift 3.11 and Gloo 1.2.0
      # --set="gateway.certGenJob.setTtlAfterFinished=false"
    ;;

  knative)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm fetch --untar='true' --untardir='.' --version="${GLOO_VERSION}" \
      gloo/gloo
    kubectl create namespace "${GLOO_NAMESPACE}" && true # ignore errors
    helm upgrade --install gloo gloo/gloo \
      --namespace="${GLOO_NAMESPACE}" \
      --version="${GLOO_VERSION}" \
      --values='gloo/values-knative.yaml'
    ;;

  none) ;;

esac
