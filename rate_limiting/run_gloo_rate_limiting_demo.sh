#!/usr/bin/env bash

# Based on GlooE Rate Limiting example
# https://gloo.solo.io/gloo_routing/virtual_services/rate_limiting/simple/

# OIDC Configuration

OIDC_CLIENT_ID='gloo'
OIDC_CLIENT_SECRET='secretvalue'

OIDC_ISSUER_URL='http://dex.gloo-system.svc.cluster.local:32000/'
OIDC_APP_URL='http://localhost:8080/'
OIDC_CALLBACK_PATH='/callback'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

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

K8S_SECRET_NAME='my-oauth-secret'

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  secret/"${K8S_SECRET_NAME}" \
  virtualservice/default

# Start port-forwards to allow DEX OIDC Provider to work with Gloo
port_forward_deployment 'gloo-system' 'dex' '32000:5556'

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
  extension: $(base64 <<EOF2
config:
  client_secret: ${OIDC_CLIENT_SECRET}
EOF2
)
EOF

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
#   --oidc-scope='email'

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
    routes:
    - matcher:
        prefix: /vets
      routeAction:
        single:
          upstream:
            name: default-petclinic-8080
            namespace: gloo-system
      routePlugins:
        extensions:
          configs:
            extauth:
              disable: true
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
                scopes:
                - email
          rate-limit:
            anonymous_limits:
              requests_per_unit: 5
              unit: MINUTE
            authorized_limits:
              requests_per_unit: 10
              unit: MINUTE
EOF

# kubectl --namespace gloo-system get virtualservice/default --output yaml

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

# Anonymous access
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NORMAL=$(tput sgr0)

printf "\nFirst 5 calls should succeed (200); last 5 should fail (429)\n"
for i in {1..10}; do
  ci="$(tput setaf $i)${i}${NORMAL}"

  STATUS="$(curl --silent --write-out "%{http_code}" --output /dev/null "${PROXY_URL}/vets")"
  case "${STATUS}" in
    200) STATUS="${GREEN}200 OK${NORMAL}" ;;
    429) STATUS="${YELLOW}429 Too Many Requests${NORMAL}" ;;
    *  ) STATUS="${RED}${STATUS}${NORMAL}" ;;
  esac

  printf "Call %s - Status: %s\n" "$ci" "$STATUS"
done

# Authenticate using user: admin@example.com password: password
# Should be able to refresh page 10 times per minute

# open "${PROXY_URL}"
open -a "Google Chrome" --new --args --incognito "${PROXY_URL}/"
