#!/usr/bin/env bash

# Based on Gloo mTLS example
# https://gloo.solo.io/gloo_integrations/service_mesh/gloo_istio_mtls/

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

cleanup_port_forward_deployment 'gateway-proxy'

kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/prodpage

kubectl --namespace='gloo-system' patch upstream/default-productpage-9080 \
  --type='json' \
  --patch='[
  {
    "op": "remove",
    "path": "/spec/upstreamSpec/sslConfig"
  }
]'

kubectl --namespace='gloo-system' patch deployment/gateway-proxy \
  --type='json' \
  --patch='[
  {
    "op": "remove",
    "path": "/spec/template/spec/volumes/1"
  },
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/volumeMounts/1"
  }
]'

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/platform/kube/bookinfo.yaml' \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/networking/destination-rule-all-mtls.yaml'

kubectl patch namespace/default \
  --type='json' \
  --patch='[
  {
    "op": "remove",
    "path": "/metadata/labels/istio-injection"
  }
]'

helm delete --purge istio
helm delete --purge istio-init

kubectl delete namespace istio-system
