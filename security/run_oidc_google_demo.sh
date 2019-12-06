#!/usr/bin/env bash

# Based on GlooE Custom Auth server example
# https://gloo.solo.io/enterprise/authentication/oidc/

# OIDC Configuration
OIDC_ISSUER_URL='https://accounts.google.com/'
OIDC_APP_URL='http://localhost:8080/'
OIDC_CALLBACK_PATH='/callback'

# https://console.developers.google.com/apis/credentials
# OIDC_CLIENT_ID='<google id>'
# OIDC_CLIENT_SECRET='<google secret>'

# Configure Credentials
if [[ -f "${HOME}/scripts/secret/google_oidc_credentials.sh" ]]; then
  # OIDC_CLIENT_ID='<google id>'
  # OIDC_CLIENT_SECRET='<google secret>'
  source "${HOME}/scripts/secret/google_oidc_credentials.sh"
fi

if [[ -z "${OIDC_CLIENT_ID}" ]] || [[ -z "${OIDC_CLIENT_SECRET}" ]]; then
  echo 'Must set OAuth OIDC_CLIENT_ID and OIDC_CLIENT_SECRET environment variables'
  exit
fi

K8S_SECRET_NAME='my-oauth-secret'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup old examples
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${K8S_SECRET_NAME}"

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml"

# glooctl create secret oauth \
#   --name="${K8S_SECRET_NAME}" \
#   --namespace='gloo-system' \
#   --client-secret="${OIDC_CLIENT_SECRET}"

kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  annotations:
    resource_kind: '*v1.Secret'
  name: ${K8S_SECRET_NAME}
  namespace: gloo-system
data:
  extension: $(base64 --wrap=0 <<EOF2
config:
  client_secret: ${OIDC_CLIENT_SECRET}
EOF2
)
EOF

kubectl apply --filename - <<EOF
apiVersion: enterprise.gloo.solo.io/v1
kind: AuthConfig
metadata:
  name: my-oidc
  namespace: gloo-system
spec:
  configs:
  - oauth:
      app_url: ${OIDC_APP_URL}
      callback_path: ${OIDC_CALLBACK_PATH}
      client_id: ${OIDC_CLIENT_ID}
      client_secret_ref:
        name: ${K8S_SECRET_NAME}
        namespace: gloo-system
      issuer_url: ${OIDC_ISSUER_URL}
      scopes: []
EOF

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  displayName: default
  virtualHost:
    domains:
    - '*'
    name: gloo-system.default
    routes:
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: gloo-system
    options:
      extauth:
        config_ref:
          name: my-oidc
          namespace: gloo-system
EOF

# kubectl --namespace gloo-system get virtualservice/default --output yaml

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open http://localhost:8080/
open -a "Google Chrome" --new --args --incognito 'http://localhost:8080/'
