#!/usr/bin/env bash

# Based on GlooE OPA and OIDC example
# https://gloo.solo.io/gloo_routing/virtual_services/security/opa/#open-policy-agent-and-open-id-connect

PROXY_PORT=9080
WEB_UI_PORT=9088

POLICY_K8S_CONFIGMAP='allow-jwt'
K8S_SECRET_NAME='my-oauth-secret'

# OIDC Configuration

OIDC_CLIENT_ID='gloo'
OIDC_CLIENT_SECRET='secretvalue'

OIDC_ISSUER_URL='http://dex.gloo-system.svc.cluster.local:32000/'
OIDC_APP_URL="http://localhost:${PROXY_PORT}/"
OIDC_CALLBACK_PATH='/callback'

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

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  configmap/"${POLICY_K8S_CONFIGMAP}" \
  secret/"${K8S_SECRET_NAME}" \
  virtualservice/default

#
# Configure OIDC DEX Provider
#

# Install DEX OIDC Provider https://github.com/dexidp/dex
# DEX is not required for Gloo extauth; it is here as an OIDC provider to simplify example
helm upgrade --install dex stable/dex \
  --namespace='gloo-system' \
  --wait \
  --values - <<EOF
grpc: false

config:
  issuer: http://dex.gloo-system.svc.cluster.local:32000

  staticClients:
  - id: ${OIDC_CLIENT_ID}
    redirectURIs:
    - http://localhost:${PROXY_PORT}/callback
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

# Start port-forwards to allow DEX OIDC Provider to work with Gloo
port_forward_deployment 'gloo-system' 'dex' '32000:5556'

#
# Configure Open Policy Agent policies
#

# Create OPA policy ConfigMap
kubectl --namespace='gloo-system' create configmap "${POLICY_K8S_CONFIGMAP}" \
  --from-file="${SCRIPT_DIR}/allow-jwt.rego"

#
# Configure AuthConfig
#

# Create Kubernetes Secret containing OIDC Client Secret
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
  extension: $(
  base64 <<EOF2
config:
  client_secret: ${OIDC_CLIENT_SECRET}
EOF2
)
EOF

# Create Gloo AuthConfig for AuthN (OIDC) and AuthZ (OPA)
kubectl apply --filename - <<EOF
apiVersion: enterprise.gloo.solo.io/v1
kind: AuthConfig
metadata:
  name: petclinic-auth
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
      scopes:
      - email
  - opa_auth:
      modules:
      - name: ${POLICY_K8S_CONFIGMAP}
        namespace: gloo-system
      query: data.test.allow == true
EOF

#
# Install example services and external upstreams
#

# Install petclinic application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-db.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic.yaml" \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petclinic-vets.yaml"

# Install petstore app to show OpenAPI
kubectl --namespace='default' apply \
  --filename "${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Configure AWS upstreams
if [[ -f "${HOME}/scripts/secret/aws_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl --namespace='gloo-system' delete \
    --ignore-not-found='true' \
    secret/aws \
    upstream/aws

  # glooctl create secret aws --name 'aws' --namespace 'gloo-system' --access-key '<access key>' --secret-key '<secret key>'
  source "${HOME}/scripts/secret/aws_credentials.sh"

  kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: aws
  namespace: gloo-system
spec:
  upstreamSpec:
    aws:
      region: us-east-1
      secretRef:
        name: aws
        namespace: gloo-system
EOF
fi

#
# Configure Traffic Routing rules
#

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system' \
#   --enable-oidc-auth \
#   --oidc-auth-app-url="${OIDC_APP_URL}" \
#   --oidc-auth-callback-path="${OIDC_CALLBACK_PATH}" \
#   --oidc-auth-client-id="${OIDC_CLIENT_ID}" \
#   --oidc-auth-client-secret-name="${K8S_SECRET_NAME}" \
#   --oidc-auth-client-secret-namespace='gloo-system' \
#   --oidc-auth-issuer-url="${OIDC_ISSUER_URL}" \
#   --oidc-scope='email' \
#   --enable-opa-auth \
#   --opa-query='data.test.allow == true' \
#   --opa-module-ref="gloo-system.${POLICY_K8S_CONFIGMAP}"

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
  virtualHost:
    domains:
    - '*'
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
            config_ref:
              name: petclinic-auth
              namespace: gloo-system
EOF

#
# Enable localhost access to cluster and open web brower clients
#

# Expose and open in browser GlooE Web UI Console
port_forward_deployment 'gloo-system' 'api-server' "${WEB_UI_PORT:-9088}:8080"

open "http://localhost:${WEB_UI_PORT:-9088}/"

# Open in browser petclinic home page
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' "${PROXY_PORT:-9080}:8080"

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open "http://localhost:${PROXY_PORT:-9080}/"
open -a "Google Chrome" --new --args --incognito "http://localhost:${PROXY_PORT:-9080}/"
