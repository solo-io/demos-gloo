#!/usr/bin/env bash

# Expects
# brew install kubernetes-cli kubernetes-helm skaffold httpie

# Optional
# brew install go jq openshift-cli; brew cask install minikube minishift

# Will exit script if we would use an uninitialised variable:
set -o nounset
# Will exit script when a simple command (not a control structure) fails:
set -o errexit

function print_error {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/working_environment.sh"

GLOO_ENT_VERSION='0.19.0'
GLOO_OSS_VERSION='0.20.1'

K8S_TOOL=${K8S_TOOL:-kind} # kind, minikube, minishift, gcloud

case $K8S_TOOL in
  kind)
    if [[ -x $(command -v go) ]] && [[ $(go version) =~ go1.13 ]]; then
      # Install latest version of kind https://kind.sigs.k8s.io/
      GO111MODULE='on' go get sigs.k8s.io/kind@v0.5.1
    fi

    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-kind}

    # Delete existing cluster, i.e. restart cluster
    if [[ $(kind get clusters) == *"$DEMO_CLUSTER_NAME"* ]]; then
      kind delete cluster --name "$DEMO_CLUSTER_NAME"
    fi

    # Setup local Kubernetes cluster using kind (Kubernetes IN Docker) with control plane and worker nodes
    kind create cluster --name "$DEMO_CLUSTER_NAME" --wait 60s

    # Configure environment for kubectl to connect to kind cluster
    KUBECONFIG=$(kind get kubeconfig-path --name="$DEMO_CLUSTER_NAME")
    export KUBECONFIG
    ;;

  minikube)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-minikube}

    # for Mac (can also use Virtual Box)
    # brew install hyperkit; brew cask install minikube
    # minikube config set vm-driver hyperkit

    # minikube config set cpus 4
    # minikube config set memory 4096

    minikube delete --profile "$DEMO_CLUSTER_NAME" && true # Ignore errors
    minikube start --profile "$DEMO_CLUSTER_NAME" \
      --cpus=4 \
      --memory=8192mb \
      --wait=true \
      --kubernetes-version='v1.15.4'

    source <(minikube docker-env -p "$DEMO_CLUSTER_NAME")
    ;;

  minishift)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-minishift}

    # for Mac (can also use Virtual Box)
    # brew install hyperkit; brew cask install minishift
    # minishift config set vm-driver hyperkit

    # minishift config set cpus 4
    # minishift config set memory 4096

    minishift delete --profile "$DEMO_CLUSTER_NAME" --force && true # Ignore errors
    minishift start --profile "$DEMO_CLUSTER_NAME"

    minishift addons install --defaults
    minishift addons apply admin-user

    # Login as administrator
    oc login --username='system:admin'

    # Add security context constraint to users or a service account
    oc --namespace gloo-system adm policy add-scc-to-user anyuid --serviceaccount='glooe-prometheus-server'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid --serviceaccount='glooe-prometheus-kube-state-metrics'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid --serviceaccount='glooe-grafana'
    oc --namespace gloo-system adm policy add-scc-to-user anyuid --serviceaccount='default'

    source <(minishift docker-env --profile "$DEMO_CLUSTER_NAME")
    ;;

  gcloud)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-gke-gloo}

    gcloud container clusters delete "$DEMO_CLUSTER_NAME" --quiet && true # Ignore errors
    gcloud container clusters create "$DEMO_CLUSTER_NAME" \
      --cluster-version='latest' \
      --machine-type='n1-standard-2' \
      --num-nodes='3' \
      --labels='creator=scranton'

    gcloud container clusters get-credentials "$DEMO_CLUSTER_NAME"

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole='cluster-admin' \
      --user="$(gcloud config get-value account)"
    ;;
esac

# Tell skaffold how to connect to local Kubernetes cluster running in non-default profile name
if [[ -x $(command -v skaffold) ]]; then
  skaffold config set --kube-context="$(kubectl config current-context)" local-cluster true
fi

TILLER_MODE=${TILLER_MODE:-local} # local, cluster, none

unset HELM_HOST

case $TILLER_MODE in
  local)
    # Run Tiller locally (external) to Kubernetes cluster as it's faster
    TILLER_PID_FILE="$SCRIPT_DIR/tiller.pid"
    if [[ -f $TILLER_PID_FILE ]]; then
      xargs kill <"$TILLER_PID_FILE" && true # Ignore errors killing old Tiller process
      rm "$TILLER_PID_FILE"
    fi
    TILLER_PORT=":44134"
    ( (tiller --storage='secret' --listen="$TILLER_PORT") & echo $! > "$TILLER_PID_FILE" & )
    export HELM_HOST=$TILLER_PORT
    ;;

  cluster)
    # Install Helm and Tiller
    kubectl --namespace='kube-system' create serviceaccount tiller

    kubectl create clusterrolebinding tiller-cluster-rule \
      --clusterrole='cluster-admin' \
      --serviceaccount='kube-system:tiller'

    if [[ $(kubectl version --output json | jq --raw-output '.serverVersion.minor') == '16' ]]; then
      # Tiller install is broken with Kubernetes 1.16 as Deployment is now `apps/v1`
      helm init --service-account tiller \
        --override spec.selector.matchLabels.'name'='tiller',spec.selector.matchLabels.'app'='helm' \
        --output yaml | sed 's@apiVersion: extensions/v1beta1@apiVersion: apps/v1@' | kubectl apply -f -
    else
      helm init --service-account tiller
    fi

    # Wait for tiller to be fully running
    kubectl --namespace='kube-system' rollout status deployment/tiller-deploy --watch='true'
    ;;

    none)
      ;;
esac

GLOO_MODE=${GLOO_MODE:-oss} # oss, ent, knative, none

case $GLOO_MODE in
  ent)
    GLOO_VERSION=${GLOO_VERSION:-$GLOO_ENT_VERSION}

    if [[ -f ~/scripts/secret/glooe_license_key.sh ]]; then
      # export GLOOE_LICENSE_KEY=<valid key>
      source ~/scripts/secret/glooe_license_key.sh
    fi
    if [[ -z $GLOOE_LICENSE_KEY ]]; then
      echo 'You must set GLOOE_LICENSE_KEY with GlooE activation key'
      exit
    fi

    helm repo add glooe 'http://storage.googleapis.com/gloo-ee-helm'
    helm repo update
    helm upgrade --install glooe glooe/gloo-ee \
      --namespace='gloo-system' \
      --set='gloo.gatewayProxies.gatewayProxyV2.readConfig=true' \
      --set-string="license_key=$GLOOE_LICENSE_KEY" \
      --version="$GLOO_VERSION"
    ;;

  oss)
    GLOO_VERSION=${GLOO_VERSION:-$GLOO_OSS_VERSION}

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm upgrade --install gloo gloo/gloo \
      --namespace='gloo-system' \
      --set='gatewayProxies.gatewayProxyV2.readConfig=true' \
      --version="$GLOO_VERSION"
    ;;

  knative)
    GLOO_VERSION=${GLOO_VERSION:-$GLOO_OSS_VERSION}

    helm repo add gloo 'https://storage.googleapis.com/solo-public-helm'
    helm repo update
    helm fetch --untar='true' --untardir='.' --version="$GLOO_VERSION" \
      gloo/gloo
    helm upgrade --install gloo gloo/gloo \
      --namespace='gloo-system' \
      --values='gloo/values-knative.yaml' \
      --version="$GLOO_VERSION"
    ;;

  none)
    ;;
esac

# Wait for GlooE gateway-proxy to be fully deployed and running
# kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'

# kubectl --namespace gloo-system port-forward deploy/gateway-proxy-v2 8080:8080 >/dev/null &
