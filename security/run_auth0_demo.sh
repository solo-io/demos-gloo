#!/usr/bin/env bash
# shellcheck disable=SC2034

# Based on GlooE JWT Access Control except using Auth0 with Client Credential Flow
# https://gloo.solo.io/gloo_routing/virtual_services/security/jwt/access_control/

# brew install kubernetes-cli httpie jq

# Auth0 Configuration - must set all
# AUTH0_DOMAIN=''
# AUTH0_AUDIENCE=''
# AUTH0_CLIENT_ID=''
# AUTH0_CLIENT_SECRET=''

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Configure Auth0 Credentials
if [[ -f "${HOME}/scripts/secret/auth0_credentials.sh" ]]; then
  # export AUTH0_DOMAIN='<Auth0 Domain>'
  # export AUTH0_AUDIENCE='<Auth0 Audience>'
  # export AUTH0_CLIENT_ID='<Auth0 Client ID>'
  # export AUTH0_CLIENT_SECRET='<Auth0 Client Secret>'
  source "${HOME}/scripts/secret/auth0_credentials.sh"
fi

if [[ -z "${AUTH0_CLIENT_ID}" ]] || [[ -z "${AUTH0_CLIENT_SECRET}" ]]; then
  echo 'Must set Auth0 AUTH0_CLIENT_ID and AUTH0_CLIENT_SECRET environment variables'
  exit
fi

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

UPSTREAM_NAME='auth0'

# Cleanup old examples
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  upstream/"${UPSTREAM_NAME}"

kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: "${UPSTREAM_NAME}"
  namespace: gloo-system
spec:
  upstreamSpec:
    static:
      hosts:
      - addr: ${AUTH0_DOMAIN}
        port: 443
      useTls: true
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
            name: default-petstore-8080
            namespace: gloo-system
    virtualHostOptions:
      extensions:
        configs:
          jwt:
            providers:
              auth0:
                issuer: "https://${AUTH0_DOMAIN}/"
                audiences:
                - ${AUTH0_AUDIENCE}
                keepToken: true
                jwks:
                  remote:
                    url: https://${AUTH0_DOMAIN}/.well-known/jwks.json
                    upstreamRef:
                      name: "${UPSTREAM_NAME}"
                      namespace: gloo-system
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

# GLOO_PROXY_URL=$(glooctl proxy url)
GLOO_PROXY_URL='http://localhost:8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

sleep 5

# Authenticate with Auth0 to get Access Token
# AUTH0_TOKEN=$(curl --silent --request POST \
#   --url "https://${AUTH0_DOMAIN}/oauth/token" \
#   --header 'content-type: application/json' \
#   --data @- <<EOF | jq --raw-output '.access_token'
# {
#   "grant_type":"client_credentials",
#   "audience":"${AUTH0_AUDIENCE}",
#   "client_id":"${AUTH0_CLIENT_ID}",
#   "client_secret":"${AUTH0_CLIENT_SECRET}"
# }
# EOF
# )
AUTH0_TOKEN=$(
  http POST "https://${AUTH0_DOMAIN}/oauth/token" \
    grant_type=client_credentials \
    audience="${AUTH0_AUDIENCE}" \
    client_id="${AUTH0_CLIENT_ID}" \
    client_secret="${AUTH0_CLIENT_SECRET}" | jq --raw-output '.access_token'
)

# Call Gloo with Bearer Token
printf "\nShould return 200 OK\n"
# curl --verbose --silent \
#   --header "authorization: Bearer ${AUTH0_TOKEN}" \
#   "${GLOO_PROXY_URL}/api/pets"
http "${GLOO_PROXY_URL}/api/pets" "authorization:Bearer ${AUTH0_TOKEN}"

# printf "Auth0 Token = %s" "${AUTH0_TOKEN}"

printf "\nShould return 401 Unauthorized\n"
TAMPERED_AUTH0_TOKEN='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IlFrSkZSRUkyT0RkR1FrWkRPRU13TUVRNVFVUXdRVEUxUmpoRk9FSXpRVEpCTkVGQlFrSkROdyJ9.eyJpc3NiOiJodHRwczovL3NvbG9sYWJzLmF1dGgwLmNvbS8iLCJzdWIiOiJxWU02eVkwb0VKSGtpUmY1dW5tYmRNTDFkNGtkdmxHMkBjbGllbnRzIiwiYXVkIjoiL3BldHN0b3JlIiwiaWF0IjoxNTcyNDUzMjIzLCJleHAiOjE1NzI1Mzk2MjMsImF6cCI6InFZTTZ5WTBvRUpIa2lSZjV1bm1iZE1MMWQ0a2R2bEcyIiwiZ3R5IjoiY2xpZW50LWNyZWRlbnRpYWxzIn0.aNoIvX1M4_3PqCc5DGZWp2dHmiRGqZUZ_CZHyWcvd_iTA2WXIlJRV55b822HB7G8AHOIrrNzFwdQEb4TtH9KGa13lE28OezCSvlua_7pXzq_B_0RhxEbLFILDZceFmXSD09dXczrSv-tQhJNBPMUC2y-WOYqaRfavhr9vS6_7saNg7F5c9-7Ay7sI8O13-LgvN9nPJAPMe3xKen-WCK0xbAeyVmrWh7yuNK9bPW14Ga1xfDbhh8bMouGh57P7bOhY_v65HeIsKYszTH_WWpZ5XO9GRDrkyY6Yeba0PbujmINkoP8hE7xQ9zPNRUPj0oGPPPptOLG87j8Tye3YkoROw'
# curl --verbose --silent \
#   --header "authorization: Bearer ${TAMPERED_AUTH0_TOKEN}" \
#   "${GLOO_PROXY_URL}/api/pets"
http "${GLOO_PROXY_URL}/api/pets" "authorization:Bearer ${TAMPERED_AUTH0_TOKEN}"
