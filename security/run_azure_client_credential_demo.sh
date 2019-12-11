#!/usr/bin/env bash
# shellcheck disable=SC2034

# Based on GlooE JWT Access Control except using Auth0 with Client Credential Flow
# https://gloo.solo.io/gloo_routing/virtual_services/security/jwt/access_control/

# brew install kubernetes-cli httpie jq

# Azure AD configuration
# AZURE_TENANT='<tenant>'
# AZURE_DOMAIN="login.microsoftonline.com"
# OAUTH_CLIENT_ID='<client id>'
# OUATH_CLIENT_SECRET='<client secret>'
# OAUTH_AUDIENCE='<application id>'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Configure Auth0 Credentials
if [[ -f "${HOME}/scripts/secret/azure_credentials.sh" ]]; then
  # AZURE_TENANT='<tenant>'
  # AZURE_DOMAIN="login.microsoftonline.com"
  # OAUTH_CLIENT_ID='<client id>'
  # OUATH_CLIENT_SECRET='<client secret>'
  # OAUTH_AUDIENCE='<application id>'
  source "${HOME}/scripts/secret/azure_credentials.sh"
fi

if [[ -z "${OAUTH_CLIENT_ID}" ]] || [[ -z "${OUATH_CLIENT_SECRET}" ]]; then
  echo 'Must set OAUTH_CLIENT_ID and OUATH_CLIENT_SECRET environment variables'
  exit
fi

UPSTREAM_NAME='oauth'

# Cleanup old examples
kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  virtualservice/default \
  upstream/"${UPSTREAM_NAME}"

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: "${UPSTREAM_NAME}"
  namespace: "${GLOO_NAMESPACE}"
spec:
  static:
    hosts:
    - addr: "${AZURE_DOMAIN}"
      port: 443
    useTls: true
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
            name: default-petstore-8080
            namespace: "${GLOO_NAMESPACE}"
    options:
      jwt:
        providers:
          azure:
            issuer: "https://${AZURE_DOMAIN}/${AZURE_TENANT}/v2.0"
            audiences:
            - "${OAUTH_CLIENT_ID}"
            keep_token: true
            jwks:
              remote:
                url: "https://${AZURE_DOMAIN}/${AZURE_TENANT}/discovery/v2.0/keys"
                upstream_ref:
                  name: "${UPSTREAM_NAME}"
                  namespace: "${GLOO_NAMESPACE}"
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' '8080'

# GLOO_PROXY_URL=$(glooctl proxy url)
GLOO_PROXY_URL='http://localhost:8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

sleep 5

# Authenticate with to get Access Token
# ACCESS_TOKEN=$(curl --silent --request POST \
#   --url "https://${AZURE_DOMAIN}/${AZURE_TENANT}/oauth2/v2.0/token" \
#   --form 'grant_type=client_credentials' \
#   --form "scope=${OAUTH_AUDIENCE}/.default" \
#   --form "client_id=${OAUTH_CLIENT_ID}" \
#   --form "client_secret=${OUATH_CLIENT_SECRET}" | jq --raw-output '.access_token'
# )
ACCESS_TOKEN=$(
  http --form POST "https://${AZURE_DOMAIN}/${AZURE_TENANT}/oauth2/v2.0/token" \
    grant_type=client_credentials \
    scope="${OAUTH_AUDIENCE}/.default" \
    client_id="${OAUTH_CLIENT_ID}" \
    client_secret="${OUATH_CLIENT_SECRET}" | jq --raw-output '.access_token'
)

# printf "Access Token '%s'" "${ACCESS_TOKEN}"

# Call Gloo with Bearer Token
printf "\nShould return 200 OK\n"
# curl --verbose --silent \
#   --header "authorization: Bearer ${ACCESS_TOKEN}" \
#   "${GLOO_PROXY_URL}/api/pets"
http "${GLOO_PROXY_URL}/api/pets" "authorization:Bearer ${ACCESS_TOKEN}"

# printf "Auth0 Token = %s" "${ACCESS_TOKEN}"

printf "\nShould return 401 Unauthorized\n"
TAMPERED_ACCESS_TOKEN='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IlFrSkZSRUkyT0RkR1FrWkRPRU13TUVRNVFVUXdRVEUxUmpoRk9FSXpRVEpCTkVGQlFrSkROdyJ9.eyJpc3NiOiJodHRwczovL3NvbG9sYWJzLmF1dGgwLmNvbS8iLCJzdWIiOiJxWU02eVkwb0VKSGtpUmY1dW5tYmRNTDFkNGtkdmxHMkBjbGllbnRzIiwiYXVkIjoiL3BldHN0b3JlIiwiaWF0IjoxNTcyNDUzMjIzLCJleHAiOjE1NzI1Mzk2MjMsImF6cCI6InFZTTZ5WTBvRUpIa2lSZjV1bm1iZE1MMWQ0a2R2bEcyIiwiZ3R5IjoiY2xpZW50LWNyZWRlbnRpYWxzIn0.aNoIvX1M4_3PqCc5DGZWp2dHmiRGqZUZ_CZHyWcvd_iTA2WXIlJRV55b822HB7G8AHOIrrNzFwdQEb4TtH9KGa13lE28OezCSvlua_7pXzq_B_0RhxEbLFILDZceFmXSD09dXczrSv-tQhJNBPMUC2y-WOYqaRfavhr9vS6_7saNg7F5c9-7Ay7sI8O13-LgvN9nPJAPMe3xKen-WCK0xbAeyVmrWh7yuNK9bPW14Ga1xfDbhh8bMouGh57P7bOhY_v65HeIsKYszTH_WWpZ5XO9GRDrkyY6Yeba0PbujmINkoP8hE7xQ9zPNRUPj0oGPPPptOLG87j8Tye3YkoROw'
# curl --verbose --silent \
#   --header "authorization: Bearer ${TAMPERED_ACCESS_TOKEN}" \
#   "${GLOO_PROXY_URL}/api/pets"
http "${GLOO_PROXY_URL}/api/pets" "authorization:Bearer ${TAMPERED_ACCESS_TOKEN}"
