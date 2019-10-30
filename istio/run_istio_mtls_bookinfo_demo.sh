#!/usr/bin/env bash

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

source "${SCRIPT_DIR}/../working_environment.sh"

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Install Istio
helm repo add istio.io 'https://storage.googleapis.com/istio-release/releases/1.3.3/charts/'

# Install Istio CRDs
helm upgrade --install istio-init istio.io/istio-init \
  --namespace='istio-system'

# Wait for all CRDs to be registered
while [[ $(kubectl get crds | grep -c 'istio.io') -lt '23' ]]; do
  sleep 2
done

# Install Istio services
helm upgrade --install istio istio.io/istio \
  --namespace='istio-system' \
  --set='mtls.enabled=false'

# Install Bookinfo example app
kubectl label --overwrite='true' namespace/default istio-injection='enabled'

kubectl --namespace='default' apply \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/platform/kube/bookinfo.yaml'

kubectl --namespace='default' rollout status deployment/productpage-v1 --watch='true'

kubectl get services

RATINGS_POD_NAME=$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')
PRODUCTPAGE_POD_NAME=$(kubectl get pod -l app=productpage -o jsonpath={.items..metadata.name})

kubectl exec -it "${RATINGS_POD_NAME}" -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

istioctl authn tls-check "${PRODUCTPAGE_POD_NAME}" reviews.default.svc.cluster.local

# Install Istio Gateway
kubectl apply \
  --filename 'https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/networking/bookinfo-gateway.yaml'

kubectl get gateway

kubectl get svc istio-ingressgateway -n istio-system

INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
GATEWAY_URL="${INGRESS_HOST}:${INGRESS_PORT}"
echo "${GATEWAY_URL}"

curl -s "http://${GATEWAY_URL}/productpage" | grep -o "<title>.*</title>"

kubectl apply --filename - <<EOF
apiVersion: "authentication.istio.io/v1alpha1"
kind: "Policy"
metadata:
  name: "default"
  namespace: "default"
spec:
  peers:
  - mtls: {}
---
apiVersion: "networking.istio.io/v1alpha3"
kind: "DestinationRule"
metadata:
  name: "default"
  namespace: "default"
spec:
  host: "*.default.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF

kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- ls /etc/certs

kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- cat /etc/certs/cert-chain.pem | openssl x509 -text -noout  | grep Validity -A 2

kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- cat /etc/certs/cert-chain.pem | openssl x509 -text -noout  | grep 'Subject Alternative Name' -A 1

istioctl authn tls-check "${PRODUCTPAGE_POD_NAME}" reviews.default.svc.cluster.local

kubectl exec -it "${RATINGS_POD_NAME}" -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

# Fail - 56
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl http://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n'

# Fail - 35
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl https://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n' -k

# Succeed
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl https://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n' --key /etc/certs/key.pem --cert /etc/certs/cert-chain.pem --cacert /etc/certs/root-cert.pem -k

curl -s "http://${GATEWAY_URL}/productpage" | grep -o "<title>.*</title>"
