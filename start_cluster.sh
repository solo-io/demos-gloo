#!/usr/bin/env bash
#
# Starts up a Kubernetes clusterbased on settings in working_environment.sh

# Expects
# brew install kubernetes-cli kubernetes-helm skaffold

# Optional
# brew install go openshift-cli; brew cask install minikube minishift

GLOO_ENT_VERSION='0.21.0'
GLOO_OSS_VERSION='0.21.3'

K8S_VERSION='v1.15.6'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/common_scripts.sh"
source "${SCRIPT_DIR}/working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

K8S_TOOL="${K8S_TOOL:-kind}" # kind, minikube, minishift, gcloud, custom

case "${K8S_TOOL}" in
  kind)
    if [[ -x "$(command -v go)" ]] && [[ "$(go version)" =~ go1.13 ]]; then
      # Install latest version of kind https://kind.sigs.k8s.io/
      GO111MODULE='on' go get sigs.k8s.io/kind@v0.6.0
    fi

    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-kind}"

    # Delete existing cluster, i.e. restart cluster
    if [[ "$(kind get clusters)" == *"${DEMO_CLUSTER_NAME}"* ]]; then
      kind delete cluster --name="${DEMO_CLUSTER_NAME}"
    fi

    # Setup local Kubernetes cluster using kind (Kubernetes IN Docker) with
    # control plane and worker nodes
    kind create cluster --name="${DEMO_CLUSTER_NAME}" --image=kindest/node:"${K8S_VERSION}" --wait='60s'
    ;;

  minikube)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-minikube}"

    # for Mac (can also use Virtual Box)
    # brew install hyperkit; brew cask install minikube
    # minikube config set vm-driver hyperkit

    # minikube config set cpus 4
    # minikube config set memory 4096

    minikube delete --profile="${DEMO_CLUSTER_NAME}" && true # Ignore errors
    minikube start --profile="${DEMO_CLUSTER_NAME}" \
      --cpus='4' \
      --memory='8192mb' \
      --wait='true' \
      --kubernetes-version="${K8S_VERSION}"

    source <(minikube docker-env --profile="${DEMO_CLUSTER_NAME}")
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
    gcloud beta container clusters create "${DEMO_CLUSTER_NAME}" \
      --release-channel='stable' \
      --machine-type='n1-standard-2' \
      --num-nodes='3' \
      --no-enable-basic-auth \
      --enable-ip-alias \
      --enable-stackdriver-kubernetes \
      --addons='HorizontalPodAutoscaling,HttpLoadBalancing' \
      --metadata='disable-legacy-endpoints=true' \
      --labels="creator=$(whoami)"
      # --preemptible \
      # --max-pods-per-node='30' \

    gcloud container clusters get-credentials "${DEMO_CLUSTER_NAME}"

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole='cluster-admin' \
      --user="$(gcloud config get-value account)"

    # Helm requires metrics API to be available, and GKE can be slow to start that
    wait_for_k8s_metrics_server

    ;;

  custom) ;;

esac

# Tell skaffold how to connect to local Kubernetes cluster running in
# non-default profile name
if [[ -x "$(command -v skaffold)" ]]; then
  skaffold config set --kube-context="$(kubectl config current-context)" \
    local-cluster true
fi

TILLER_MODE="${TILLER_MODE:-cluster}" # local, cluster, none

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
    helm upgrade --install glooe glooe/gloo-ee \
      --namespace='gloo-system' \
      --version="${GLOO_VERSION}" \
      --set="license_key=${GLOOE_LICENSE_KEY}" \
      --set="gloo.gatewayProxies.gatewayProxyV2.readConfig=true"
    ;;

  oss)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm upgrade --install gloo gloo/gloo \
      --namespace='gloo-system' \
      --version="${GLOO_VERSION}" \
      --set="gloo.gatewayProxies.gatewayProxyV2.readConfig=true"
    ;;

  knative)
    GLOO_VERSION="${GLOO_VERSION:-$GLOO_OSS_VERSION}"

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
