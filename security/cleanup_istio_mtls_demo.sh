#!/usr/bin/env bash

# Based on Gloo mTLS example
# https://gloo.solo.io/gloo_integrations/service_mesh/gloo_istio_mtls/

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

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi

kubectl --namespace='gloo-system' delete virtualservice/prodpage

kubectl --namespace='gloo-system' patch upstream/default-productpage-9080 \
  --type='json' \
  --patch='[
  {
    "op": "remove",
    "path": "/spec/upstreamSpec/sslConfig"
  }
]'

kubectl --namespace='gloo-system' patch deployment/gateway-proxy-v2 \
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
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/platform/kube/bookinfo.yaml'

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
