#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/working_environment.sh"

TILLER_MODE=${TILLER_MODE:-local}

case $TILLER_MODE in
  local)
    # Kill any Tiller process we started
    TILLER_PID_FILE='/tmp/tiller.pid'
    if [[ -f $TILLER_PID_FILE ]]; then
      xargs kill < "$TILLER_PID_FILE"
      rm "$TILLER_PID_FILE"
    fi
    unset HELM_HOST
    ;;

  cluster)
    helm ls --all --short | xargs -L1 helm delete --purge
    helm reset
    kubectl --namespace='kube-system' delete serviceaccount/tiller
    kubectl delete clusterrolebinding/tiller-cluster-rule
    ;;
esac

K8S_TOOL=${K8S_TOOL:-kind}

case $K8S_TOOL in
  kind)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-kind}

    unset KUBECONFIG

    kind delete cluster --name="$DEMO_CLUSTER_NAME"
    ;;

  minikube)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-minikube}

    minikube delete --profile="$DEMO_CLUSTER_NAME" && true # Ignore errors
    ;;

  minishift)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-minishift}

    minishift delete --profile="$DEMO_CLUSTER_NAME" --force && true # Ignore errors
    ;;

  gcloud)
    DEMO_CLUSTER_NAME=${DEMO_CLUSTER_NAME:-gke-gloo}

    gcloud container clusters delete "$DEMO_CLUSTER_NAME" --quiet && true # Ignore errors
    ;;
esac
