#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

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

set +e

printf "\nlist certs\n"
kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- ls /etc/certs

printf "\nValidate certs\n"
kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- cat /etc/certs/cert-chain.pem | openssl x509 -text -noout  | grep Validity -A 2

printf "\nget alternative name\n"
kubectl exec "${PRODUCTPAGE_POD_NAME}" -c istio-proxy -- cat /etc/certs/cert-chain.pem | openssl x509 -text -noout  | grep 'Subject Alternative Name' -A 1

printf "\ntls-check\n"
istioctl authn tls-check "${PRODUCTPAGE_POD_NAME}" reviews.default.svc.cluster.local

printf "\ncurl from ratings pod\n"
kubectl exec -it "${RATINGS_POD_NAME}" -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

printf "\nfail - ratings to unsecured product page\n"
# Fail - 56
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl http://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n'

printf "\nfail - ratings to product page with wrong cert\n"
# Fail - 35
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl https://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n' -k

printf "\nsucceed - ratings to product with correct certs\n"
# Succeed
kubectl exec "${RATINGS_POD_NAME}" -c istio-proxy -- curl https://productpage:9080/productpage -o /dev/null -s -w '%{http_code}\n' --key /etc/certs/key.pem --cert /etc/certs/cert-chain.pem --cacert /etc/certs/root-cert.pem -k

curl -s "http://${GATEWAY_URL}/productpage" | grep -o "<title>.*</title>"
