#!/usr/bin/env bash

# Based on GlooE OPA and OIDC example
# https://gloo.solo.io/gloo_routing/virtual_services/security/opa/#open-policy-agent-and-open-id-connect

# OIDC Configuration
OIDC_ISSUER_URL='http://dex.gloo-system.svc.cluster.local:32000/'
OIDC_APP_URL='http://localhost:8080/'
OIDC_CALLBACK_PATH='/callback'

OIDC_CLIENT_ID='gloo'
OIDC_CLIENT_SECRET='secretvalue'

if [[ -z "${OIDC_CLIENT_ID}" ]] || [[ -z "${OIDC_CLIENT_SECRET}" ]]; then
  echo 'Must set OAuth OIDC_CLIENT_ID and OIDC_CLIENT_SECRET environment variables'
  exit
fi

K8S_SECRET_NAME='my-oauth-secret'
POLICY_K8S_CONFIGMAP='allow-jwt'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../../common_scripts.sh"
source "${SCRIPT_DIR}/../../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup old examples
kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${K8S_SECRET_NAME}" \
  configmap/"${POLICY_K8S_CONFIGMAP}"

# Install DEX OIDC Provider https://github.com/dexidp/dex
# DEX is not required for Gloo extauth; it is here as an OIDC provider to simplify example
helm upgrade --install dex stable/dex \
  --namespace="${GLOO_NAMESPACE}" \
  --wait \
  --values - <<EOF
grpc: false

config:
  issuer: http://dex.${GLOO_NAMESPACE}.svc.cluster.local:32000

  staticClients:
  - id: ${OIDC_CLIENT_ID}
    redirectURIs:
    - 'http://localhost:8080/callback'
    name: 'GlooApp'
    secret: ${OIDC_CLIENT_SECRET}

  staticPasswords:
  - email: 'admin@example.com'
    # bcrypt hash of the string 'password'
    hash: '\$2a\$10\$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W'
    username: 'admin'
    userID: '08a8684b-db88-4b73-90a9-3cd1661f5466'
  - email: 'user@example.com'
    # bcrypt hash of the string 'password'
    hash: '\$2a\$10\$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W'
    username: 'user'
    userID: '123456789-db88-4b73-90a9-3cd1661f5466'
EOF

# Create policy ConfigMap
kubectl --namespace="${GLOO_NAMESPACE}" create configmap "${POLICY_K8S_CONFIGMAP}" \
  --from-file="${SCRIPT_DIR}/allow-jwt.rego"

# Start port-forwards to allow DEX OIDC Provider to work with Gloo
port_forward_deployment "${GLOO_NAMESPACE}" 'dex' '32000:5556'

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml"

# glooctl create secret oauth \
#   --name="${K8S_SECRET_NAME}" \
#   --namespace="${GLOO_NAMESPACE}" \
#   --client-secret="${OIDC_CLIENT_SECRET}"

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
      scopes:
      - email
  - opa_auth:
      modules:
      - name: ${POLICY_K8S_CONFIGMAP}
        namespace: "${GLOO_NAMESPACE}"
      query: data.test.allow == true
EOF

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: "${GLOO_NAMESPACE}"
spec:
  displayName: default
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: "${GLOO_NAMESPACE}"
    options:
      extauth:
        config_ref:
          name: my-oidc
          namespace: "${GLOO_NAMESPACE}"
EOF

# kubectl --namespace="${GLOO_NAMESPACE}" get virtualservice/default --output yaml

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' '8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open http://localhost:8080/
open -a "Google Chrome" --new --args --incognito 'http://localhost:8080/'
