#!/usr/bin/env bash

# Based on Gloo mTLS example
# https://gloo.solo.io/gloo_integrations/service_mesh/gloo_istio_mtls/

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

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
  --values - <<EOF
global:
  controlPlaneSecurityEnabled: true

  mtls:
    # Default setting for service-to-service mtls. Can be set explicitly using
    # destination rules or service annotations.
    enabled: true

  sds:
    enabled: true
    udsPath: "unix:/var/run/sds/uds_path"
    token:
      aud: "istio-ca"

nodeagent:
  enabled: true
  image: node-agent-k8s
  env:
    CA_PROVIDER: "Citadel"
    CA_ADDR: "istio-citadel:8060"
    VALID_TOKEN: true
EOF

# Install Bookinfo example app
kubectl label --overwrite='true' namespace/default istio-injection='enabled'

kubectl --namespace='default' apply \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/platform/kube/bookinfo.yaml' \
  --filename='https://raw.githubusercontent.com/istio/istio/release-1.3/samples/bookinfo/networking/destination-rule-all-mtls.yaml'

# kubectl --namespace='gloo-system' get deployment/gateway-proxy --output='json' > gateway-original.json

# Patch Gateway Proxy to reference Istio SDS over Unix Domain Sockets
kubectl --namespace='gloo-system' patch deployment/gateway-proxy \
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
    "path": "/spec/template/spec/volumes/-",
    "value": {
      "name": "istio-token",
      "projected": {
        "defaultMode": 420,
        "sources": [
          {
            "serviceAccountToken": {
              "audience": "istio-ca",
              "expirationSeconds": 43200,
              "path": "istio-token"
            }
          }
        ]
      }
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "mountPath": "/var/run/sds",
      "name": "sds-uds-path"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {
      "mountPath": "/var/run/secrets/tokens",
      "name": "istio-token"
    }
  }
]'

# kubectl --namespace='gloo-system' get deployment/gateway-proxy --output='json' > gateway-modified.json

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
            "tokenFileName": "/var/run/secrets/tokens/istio-token"
          }
        },
        "certificateSecretName": "default",
        "targetUri": "unix:/var/run/sds/uds_path",
        "validationContextName": "ROOTCA"
      }
    }
  }
]'

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
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-productpage-9080
            namespace: gloo-system
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

sleep 10

set +e

# PROXY_URL="$(glooctl proxy url)"
PROXY_URL='http://localhost:8080'

kubectl exec -it "$(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}')" -c ratings -- curl productpage:9080/productpage | grep -o "<title>.*</title>"

open "${PROXY_URL}/productpage"

kubectl exec "$(kubectl get pod -l app=productpage -o jsonpath={.items..metadata.name})" -c istio-proxy -- ls /etc/certs
