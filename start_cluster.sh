#!/usr/bin/env bash
#
# Starts up a Kubernetes clusterbased on settings in working_environment.sh

# Expects
# brew install kubernetes-cli kubernetes-helm skaffold httpie

# Optional
# brew install go jq openshift-cli; brew cask install minikube minishift

GLOO_ENT_VERSION='0.20.6'
GLOO_OSS_VERSION='0.20.11'

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu

function print_error() {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line ${line} of file ${file}:" >&2
  sed "${line}q;d" "${file}" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/working_environment.sh"

K8S_TOOL="${K8S_TOOL:-kind}" # kind, minikube, minishift, gcloud, custom

case "${K8S_TOOL}" in
  kind)
    if [[ -x "$(command -v go)" ]] && [[ "$(go version)" =~ go1.13 ]]; then
      # Install latest version of kind https://kind.sigs.k8s.io/
      GO111MODULE='on' go get sigs.k8s.io/kind@v0.5.1
    fi

    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-kind}"

    # Delete existing cluster, i.e. restart cluster
    if [[ "$(kind get clusters)" == *"${DEMO_CLUSTER_NAME}"* ]]; then
      kind delete cluster --name "${DEMO_CLUSTER_NAME}"
    fi

    # Setup local Kubernetes cluster using kind (Kubernetes IN Docker) with
    # control plane and worker nodes
    kind create cluster --name "${DEMO_CLUSTER_NAME}" --wait 60s

    # Configure environment for kubectl to connect to kind cluster
    KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME}")
    export KUBECONFIG
    ;;

  minikube)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-minikube}"

    # for Mac (can also use Virtual Box)
    # brew install hyperkit; brew cask install minikube
    # minikube config set vm-driver hyperkit

    # minikube config set cpus 4
    # minikube config set memory 4096

    minikube delete --profile "${DEMO_CLUSTER_NAME}" && true # Ignore errors
    minikube start --profile "${DEMO_CLUSTER_NAME}" \
      --cpus=4 \
      --memory=8192mb \
      --wait=true \
      --kubernetes-version='v1.15.4'

    source <(minikube docker-env -p "${DEMO_CLUSTER_NAME}")
    ;;

  minishift)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-minishift}"

    # for Mac (can also use Virtual Box)
    # brew install hyperkit; brew cask install minishift
    # minishift config set vm-driver hyperkit

    # minishift config set cpus 4
    # minishift config set memory 4096

    minishift delete --profile "${DEMO_CLUSTER_NAME}" --force && true # Ignore errors
    minishift start --profile "${DEMO_CLUSTER_NAME}"

    minishift addons install --defaults
    minishift addons apply admin-user

    # Login as administrator
    oc login --username='system:admin'

    # Add security context constraint to users or a service account
    oc --namespace gloo-system adm policy add-scc-to-user anyuid \
      --serviceaccount='glooe-prometheus-server'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid \
      --serviceaccount='glooe-prometheus-kube-state-metrics'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid \
      --serviceaccount='glooe-grafana'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid \
      --serviceaccount='default'

    source <(minishift docker-env --profile "${DEMO_CLUSTER_NAME}")
    ;;

  gcloud)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-gke-gloo}"

    gcloud container clusters delete "${DEMO_CLUSTER_NAME}" --quiet && true # Ignore errors
    gcloud container clusters create "${DEMO_CLUSTER_NAME}" \
      --machine-type='n1-standard-2' \
      --num-nodes='3' \
      --labels='creator=gloo-demos'

    gcloud container clusters get-credentials "${DEMO_CLUSTER_NAME}"

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole='cluster-admin' \
      --user="$(gcloud config get-value account)"
    ;;

  custom) ;;

esac

# Tell skaffold how to connect to local Kubernetes cluster running in
# non-default profile name
if [[ -x "$(command -v skaffold)" ]]; then
  skaffold config set --kube-context="$(kubectl config current-context)" \
    local-cluster true
fi

TILLER_MODE="${TILLER_MODE:-local}" # local, cluster, none

unset HELM_HOST

case "${TILLER_MODE}" in
  local)
    # Run Tiller locally (external) to Kubernetes cluster as it's faster
    TILLER_PID_FILE="${SCRIPT_DIR}/tiller.pid"
    if [[ -f "${TILLER_PID_FILE}" ]]; then
      xargs kill <"${TILLER_PID_FILE}" && true # Ignore errors
      rm "${TILLER_PID_FILE}"
    fi
    TILLER_PORT=":44134"
    tiller --storage='secret' --listen="${TILLER_PORT}" &
    echo $! >"${TILLER_PID_FILE}"
    export HELM_HOST="${TILLER_PORT}"
    ;;

  cluster)
    # Install Helm and Tiller
    kubectl --namespace='kube-system' create serviceaccount tiller

    kubectl create clusterrolebinding tiller-cluster-rule \
      --clusterrole='cluster-admin' \
      --serviceaccount='kube-system:tiller'

    helm init --service-account tiller

    # Wait for tiller to be fully running
    kubectl --namespace='kube-system' rollout status deployment/tiller-deploy \
      --watch='true'
    ;;

  none) ;;

esac

function wait_for_k8s_metrics_server() {
  # Hack to deal with delay in gcloud and other k8s clusters not starting
  # metrics server fast enough for helm
  K8S_PROXY_PID_FILE="${SCRIPT_DIR}/k8s_proxy_pf.pid"
  if [[ -f "${K8S_PROXY_PID_FILE}" ]]; then
    xargs kill <"${K8S_PROXY_PID_FILE}" && true # ignore errors
    rm "${K8S_PROXY_PID_FILE}"
  fi

  kubectl proxy --port 8001 >/dev/null &
  echo $! >"${K8S_PROXY_PID_FILE}"

  until curl --fail 'http://localhost:8001/apis/metrics.k8s.io/v1beta1/'; do
    sleep 5
  done

  if [[ -f "${K8S_PROXY_PID_FILE}" ]]; then
    xargs kill <"${K8S_PROXY_PID_FILE}" && true # ignore errors
    rm "${K8S_PROXY_PID_FILE}"
  fi
}

GLOO_MODE="${GLOO_MODE:-oss}" # oss, ent, knative, none

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

    # Helm depends on access to k8s metrics server
    wait_for_k8s_metrics_server

    helm repo add glooe 'http://storage.googleapis.com/gloo-ee-helm'
    helm repo update
    helm upgrade --install glooe glooe/gloo-ee \
      --namespace='gloo-system' \
      --version="${GLOO_VERSION}" \
      --values - <<EOF
license_key: ${GLOOE_LICENSE_KEY}
gloo:
  gatewayProxies:
    gatewayProxyV2:
      readConfig: true
EOF
    ;;

  oss)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

    # Helm depends on access to k8s metrics server
    wait_for_k8s_metrics_server

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm upgrade --install gloo gloo/gloo \
      --namespace='gloo-system' \
      --version="${GLOO_VERSION}" \
      --values - <<EOF
gloo:
  gatewayProxies:
    gatewayProxyV2:
      readConfig: true
EOF
    ;;

  knative)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

    # Helm depends on access to k8s metrics server
    wait_for_k8s_metrics_server

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm fetch --untar='true' --untardir='.' --version="${GLOO_VERSION}" \
      gloo/gloo
    helm upgrade --install gloo gloo/gloo \
      --namespace='gloo-system' \
      --version="${GLOO_VERSION}" \
      --values='gloo/values-knative.yaml'
    ;;

  none) ;;

esac
