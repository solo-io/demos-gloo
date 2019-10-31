#!/usr/bin/env bash

# Based on GlooE Custom Auth server example
# https://gloo.solo.io/enterprise/authentication/oidc/

# OIDC Configuration

# OIDC_CLIENT_ID='<consumer key>'
# OIDC_CLIENT_SECRET='<consumer secret>'

OIDC_ISSUER_URL='https://login.salesforce.com/'
OIDC_APP_URL='http://localhost:8080/'
OIDC_CALLBACK_PATH='http://localhost:8080/callback'

K8S_SECRET_NAME='my-oauth-secret'

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

# Configure Auth0 Credentials
if [[ -f "${HOME}/scripts/secret/sfdc_oidc_credentials.sh" ]]; then
  # OIDC_CLIENT_ID='<consumer key>'
  # OIDC_CLIENT_SECRET='<consumer secret>'
  source "${HOME}/scripts/secret/sfdc_oidc_credentials.sh"
fi

if [[ -z "${OIDC_CLIENT_ID}" ]] || [[ -z "${OIDC_CLIENT_SECRET}" ]]; then
  echo 'Must set OAuth OIDC_CLIENT_ID and OIDC_CLIENT_SECRET environment variables'
  exit
fi

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml"

# Cleanup old examples
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${K8S_SECRET_NAME}"

# printf 'glooctl version = %s' "$(glooctl --version)"

glooctl create secret oauth \
  --name="${K8S_SECRET_NAME}" \
  --namespace='gloo-system' \
  --client-secret="${OIDC_CLIENT_SECRET}"

# kubectl apply --filename - <<EOF
# apiVersion: v1
# kind: Secret
# type: Opaque
# metadata:
#   annotations:
#     resource_kind: '*v1.Secret'
#   name: ${K8S_SECRET_NAME}
#   namespace: gloo-system
# data:
#   extension: $(base64 <<EOF2
# config:
#   client_secret: ${OIDC_CLIENT_SECRET}
# EOF2
# )
# EOF

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system' \
#   --enable-oidc-auth \
#   --oidc-auth-client-secret-name="${K8S_SECRET_NAME}" \
#   --oidc-auth-client-secret-namespace='gloo-system' \
#   --oidc-auth-issuer-url="${OIDC_ISSUER_URL}" \
#   --oidc-auth-client-id="${OIDC_CLIENT_ID}" \
#   --oidc-auth-app-url="${OIDC_APP_URL}" \
#   --oidc-auth-callback-path="${OIDC_CALLBACK_PATH}"

# glooctl add route \
#   --name='default' \
#   --path-prefix='/' \
#   --dest-name='default-petclinic-8080' \
#   --dest-namespace='gloo-system'

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
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: gloo-system
    virtualHostPlugins:
      extensions:
        configs:
          extauth:
            configs:
            - oauth:
                app_url: ${OIDC_APP_URL}
                callback_path: ${OIDC_CALLBACK_PATH}
                client_id: ${OIDC_CLIENT_ID}
                client_secret_ref:
                  name: ${K8S_SECRET_NAME}
                  namespace: gloo-system
                issuer_url: ${OIDC_ISSUER_URL}
EOF

# kubectl --namespace gloo-system get virtualservice/default --output yaml

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open http://localhost:8080/
open -a "Google Chrome" --new --args --incognito 'http://localhost:8080/'
