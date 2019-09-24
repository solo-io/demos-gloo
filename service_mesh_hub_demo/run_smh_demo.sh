#!/usr/bin/env bash

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

source "$SCRIPT_DIR/../working_environment.sh"

if [[ $K8S_TOOL == "kind" ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Install Istio
helm repo add istio.io https://storage.googleapis.com/istio-release/releases/1.2.4/charts/
helm upgrade --install istio-init istio.io/istio-init \
  --namespace='istio-system'

while [[ $(kubectl get crds | grep -c 'istio.io\|certmanager.k8s.io') -lt "23" ]]; do
  sleep 2
done

helm upgrade --install istio istio.io/istio \
  --namespace='istio-system'
