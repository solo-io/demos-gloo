#!/usr/bin/env bash

# Based on Gloo mTLS example
# https://gloo.solo.io/gloo_integrations/service_mesh/gloo_istio_mtls/

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

if [[ "${K8S_TOOL}" == "kind" ]]; then
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
  --namespace='istio-system'

# Install Bookinfo example app
kubectl label --overwrite='true' namespace/default istio-injection='enabled'

kubectl --namespace='default' apply \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/platform/kube/bookinfo.yaml'

# Patch Gateway Proxy to reference Istio SDS over Unix Domain Sockets
kubectl --namespace='gloo-system' patch deployment/gateway-proxy-v2 \
  --type='json' \
  --patch='[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "hostPath": {
        "path": "/var/run/sds",
        "type": ""
      },
      "name": "sds-uds-path"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "mountPath": "/var/run/sds",
      "name": "sds-uds-path"
    }
  }
]'

kubectl --namespace='default' rollout status deployment/productpage-v1 --watch='true'

kubectl --namespace='gloo-system' patch upstream/default-productpage-9080 \
  --type='json' \
  --patch='[
  {
    "op": "add",
    "path": "/spec/upstreamSpec/sslConfig",
    "value": {
      "sds": {
        "callCredentials": {
          "fileCredentialSource": {
            "header": "istio_sds_credential_header-bin",
            "tokenFileName": "/var/run/secrets/kubernetes.io/serviceaccount/token"
          }
        },
        "certificateSecretName": "default",
        "targetUri": "unix:/var/run/sds/uds_path",
        "validationContextName": "ROOTCA"
      }
    }
  }
]'

# glooctl add route \
#   --name='prodpage' \
#   --namespace='gloo-system' \
#   --path-prefix='/' \
#   --dest-name='default-productpage-9080' \
#   --dest-namespace='gloo-system'

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: prodpage
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-productpage-9080
            namespace: gloo-system
EOF

PROXY_PID_FILE="${SCRIPT_DIR}/proxy_pf.pid"
if [[ -f "${PROXY_PID_FILE}" ]]; then
  xargs kill <"${PROXY_PID_FILE}" && true # ignore errors
  rm "${PROXY_PID_FILE}"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
(
  (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) &
  echo $! >"${PROXY_PID_FILE}" &
)

open 'http://localhost:8080/productpage'
