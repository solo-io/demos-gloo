#!/usr/bin/env bash

PROXY_PORT='9080'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Configure Auth0 Credentials
if [[ -f "${HOME}/scripts/secret/auth0_oidc_credentials.sh" ]]; then
  # export AUTH0_DOMAIN='<Auth0 Domain>'
  # export AUTH0_CLIENT_ID='<Auth0 Client ID>'
  # export AUTH0_CLIENT_SECRET='<Auth0 Client Secret>'
  source "${HOME}/scripts/secret/auth0_oidc_credentials.sh"
fi

OIDC_APP_URL="http://localhost:${PROXY_PORT}/"
OIDC_CALLBACK_PATH='/callback'
OIDC_ISSUER_URL="https://${AUTH0_DOMAIN}/"
OIDC_CLIENT_ID="${AUTH0_CLIENT_ID}"
OIDC_CLIENT_SECRET="${AUTH0_CLIENT_SECRET}"

K8S_SECRET_NAME='my-oauth-secret'

# Cleanup old examples
kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  authconfig/my-oidc \
  secret/"${K8S_SECRET_NAME}"

# glooctl create secret oauth \
#   --name="${K8S_SECRET_NAME}" \
#   --namespace="${GLOO_NAMESPACE}" \
#   --client-secret="${AUTH0_CLIENT_SECRET}"

kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  annotations:
    resource_kind: '*v1.Secret'
  name: ${K8S_SECRET_NAME}
  namespace: "${GLOO_NAMESPACE}"
data:
  oauth: $(base64 --wrap=0 <(echo -n "client_secret: ${OIDC_CLIENT_SECRET}"))
EOF

kubectl apply --filename - <<EOF
apiVersion: enterprise.gloo.solo.io/v1
kind: AuthConfig
metadata:
  name: my-oidc
  namespace: "${GLOO_NAMESPACE}"
spec:
  configs:
  - oauth:
      app_url: ${OIDC_APP_URL}
      callback_path: ${OIDC_CALLBACK_PATH}
      client_id: ${OIDC_CLIENT_ID}
      client_secret_ref:
        name: ${K8S_SECRET_NAME}
        namespace: "${GLOO_NAMESPACE}"
      issuer_url: ${OIDC_ISSUER_URL}
      scopes: []
EOF

kubectl --namespace="${GLOO_NAMESPACE}" patch virtualservice/default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  virtualHost:
    options:
      extauth:
        config_ref:
          name: my-oidc
          namespace: "${GLOO_NAMESPACE}"
EOF
)"
