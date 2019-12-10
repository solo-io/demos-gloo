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

OIDC_ISSUER_URL="http://dex.${GLOO_NAMESPACE}.svc.cluster.local:32000/"
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

# Cleanup previous example runs
kubectl --namespace="${GLOO_NAMESPACE}" delete \
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
  --namespace="${GLOO_NAMESPACE}" \
  --wait \
  --values - <<EOF
grpc: false

config:
  issuer: http://dex.${GLOO_NAMESPACE}.svc.cluster.local:32000

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
port_forward_deployment "${GLOO_NAMESPACE}" 'dex' '32000:5556'

#
# Configure Open Policy Agent policies
#

# Create OPA policy ConfigMap
kubectl --namespace="${GLOO_NAMESPACE}" create configmap "${POLICY_K8S_CONFIGMAP}" \
  --from-file="${SCRIPT_DIR}/allow-jwt.rego"

#
# Configure AuthConfig
#

# Create Kubernetes Secret containing OIDC Client Secret
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

# Create Gloo AuthConfig for AuthN (OIDC) and AuthZ (OPA)
kubectl apply --filename - <<EOF
apiVersion: enterprise.gloo.solo.io/v1
kind: AuthConfig
metadata:
  name: petclinic-auth
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

kubectl --namespace='default' label service/petstore \
  --overwrite='true' \
  'discovery.solo.io/function_discovery=enabled'

# Configure AWS upstream
if [[ -f "${HOME}/scripts/secret/aws_function_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl --namespace="${GLOO_NAMESPACE}" delete \
    --ignore-not-found='true' \
    secret/aws \
    upstream/aws

  # AWS_ACCESS_KEY='<access key>'
  # AWS_SECRET_KEY='<secret key>'
  source "${HOME}/scripts/secret/aws_function_credentials.sh"

  # glooctl create secret aws --name='aws' \
  #   --namespace="${GLOO_NAMESPACE}" \
  #   --access-key="${AWS_ACCESS_KEY}" \
  #   --secret-key="${AWS_SECRET_KEY}"

  kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: aws
  namespace: "${GLOO_NAMESPACE}"
type: Opaque
data:
  aws_access_key_id: $(base64 --wrap='0' - <(echo -n "${AWS_ACCESS_KEY}"))
  aws_secret_access_key: $(base64 --wrap='0' - <(echo -n "${AWS_SECRET_KEY}"))
EOF

  # glooctl create upstream aws \
  #   --name='aws' \
  #   --namespace="${GLOO_NAMESPACE}" \
  #   --aws-region='us-east-1' \
  #   --aws-secret-name='aws' \
  #   --aws-secret-namespace="${GLOO_NAMESPACE}"

  kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: aws
  namespace: "${GLOO_NAMESPACE}"
spec:
  aws:
    region: us-east-1
    secret_ref:
      name: aws
      namespace: "${GLOO_NAMESPACE}"
EOF
fi # Configure AWS upstream

#
# Configure Traffic Routing rules
#

# glooctl create virtualservice \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}" \
#   --enable-oidc-auth \
#   --oidc-auth-app-url="${OIDC_APP_URL}" \
#   --oidc-auth-callback-path="${OIDC_CALLBACK_PATH}" \
#   --oidc-auth-client-id="${OIDC_CLIENT_ID}" \
#   --oidc-auth-client-secret-name="${K8S_SECRET_NAME}" \
#   --oidc-auth-client-secret-namespace="${GLOO_NAMESPACE}" \
#   --oidc-auth-issuer-url="${OIDC_ISSUER_URL}" \
#   --oidc-scope='email' \
#   --enable-opa-auth \
#   --opa-query='data.test.allow == true' \
#   --opa-module-ref="${GLOO_NAMESPACE}.${POLICY_K8S_CONFIGMAP}"

# glooctl add route \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}" \
#   --path-prefix='/' \
#   --dest-name='default-petclinic-8080' \
#   --dest-namespace="${GLOO_NAMESPACE}"

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: "${GLOO_NAMESPACE}"
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
            name: default-petclinic-8080
            namespace: "${GLOO_NAMESPACE}"
    options:
      extauth:
        config_ref:
          name: petclinic-auth
          namespace: "${GLOO_NAMESPACE}"
EOF

# Enable Function Discovery for all Upstreams
kubectl --namespace="${GLOO_NAMESPACE}" patch settings/default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  discovery:
    fdsMode: BLACKLIST
EOF
)"

#
# Enable localhost access to cluster and open web brower clients
#

# Expose and open in browser GlooE Web UI Console
port_forward_deployment "${GLOO_NAMESPACE}" 'api-server' "${WEB_UI_PORT:-9088}:8080"

open "http://localhost:${WEB_UI_PORT:-9088}/"

# Open in browser petclinic home page
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' "${PROXY_PORT:-9080}:8080"

# Wait for app to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open "http://localhost:${PROXY_PORT:-9080}/"
open -a "Google Chrome" --new --args --incognito "http://localhost:${PROXY_PORT:-9080}/"
