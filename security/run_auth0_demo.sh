#!/usr/bin/env bash
# shellcheck disable=SC2034

# Based on GlooE JWT Access Control except using Auth0
# https://gloo.solo.io/gloo_routing/virtual_services/security/jwt/access_control/

# brew install kubernetes-cli httpie jq

# Auth0 Configuration - must set all
# AUTH0_DOMAIN=''
# AUTH0_AUDIENCE=''
# AUTH0_CLIENT_ID=''
# AUTH0_CLIENT_SECRET=''

# Configure Auth0 Credentials
if [[ -f ~/scripts/secret/auth0_credentials.sh ]]; then
  # export AUTH0_DOMAIN='<Auth0 Domain>'
  # export AUTH0_AUDIENCE='<Auth0 Audience>'
  # export AUTH0_CLIENT_ID='<Auth0 Client ID>'
  # export AUTH0_CLIENT_SECRET='<Auth0 Client Secret>'
  source ~/scripts/secret/auth0_credentials.sh
fi

# Will exit script if we would use an uninitialised variable:
set -o nounset
# Will exit script when a simple command (not a control structure) fails:
set -o errexit

function print_error {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

if [[ $K8S_TOOL == "kind" ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

if [[ -z $AUTH0_CLIENT_ID ]] || [[ -z $AUTH0_CLIENT_SECRET ]]; then
  echo 'Must set Auth0 AUTH0_CLIENT_ID and AUTH0_CLIENT_SECRET environment variables'
  exit
fi

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petstore.yaml"

UPSTREAM_NAME='auth0'

# Cleanup old examples
kubectl --namespace='gloo-system' delete virtualservice/default upstream/$UPSTREAM_NAME && true # ignore errors

kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: $UPSTREAM_NAME
  namespace: gloo-system
spec:
  upstreamSpec:
    static:
      hosts:
      - addr: $AUTH0_DOMAIN
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
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-petstore-8080
            namespace: gloo-system
    virtualHostPlugins:
      extensions:
        configs:
          jwt:
            providers:
              auth0:
                issuer: "https://$AUTH0_DOMAIN/"
                audiences:
                - $AUTH0_AUDIENCE
                keepToken: true
                jwks:
                  remote:
                    url: https://$AUTH0_DOMAIN/.well-known/jwks.json
                    upstreamRef:
                      name: $UPSTREAM_NAME
                      namespace: gloo-system
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
PROXY_PID_FILE="$SCRIPT_DIR/proxy_pf.pid"
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# GLOO_PROXY_URL=$(glooctl proxy url)
GLOO_PROXY_URL='http://localhost:8080'

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

sleep 5

# Authenticate with Auth0 to get Access Token
# AUTH0_TOKEN=$(curl --silent --request POST \
#   --url "https://$AUTH0_DOMAIN/oauth/token" \
#   --header 'content-type: application/json' \
#   --data @- <<EOF | jq --raw-output '.access_token'
# {
#   "grant_type":"client_credentials",
#   "audience":"$AUTH0_AUDIENCE",
#   "client_id":"$AUTH0_CLIENT_ID",
#   "client_secret":"$AUTH0_CLIENT_SECRET"
# }
# EOF
# )
AUTH0_TOKEN=$(
  http POST "https://$AUTH0_DOMAIN/oauth/token" \
    grant_type=client_credentials \
    audience=$AUTH0_AUDIENCE \
    client_id=$AUTH0_CLIENT_ID \
    client_secret=$AUTH0_CLIENT_SECRET | jq --raw-output '.access_token'
)

# Call Gloo with Bearer Token
printf "\nShould return 200 OK\n"
# curl --verbose --silent \
#   --header "authorization: Bearer $AUTH0_TOKEN" \
#   "$GLOO_PROXY_URL/api/pets"
http "$GLOO_PROXY_URL/api/pets" "authorization:Bearer $AUTH0_TOKEN"

printf "\nShould return 401 Unauthorized\n"
TAMPERED_AUTH0_TOKEN='eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6IlFrSkZSRUkyT0RkR1FrWkRPRU13TUVRNVFVUXdRVEUxUmpoRk9FSXpRVEpCTkVGQlFrSkROdyJ9.eyJpc3MiOiJodHRwczovL3NvbG9sYWJzLmF1dGgwLmNvbS8iLCJzdWIiOiJxWU02eVkwb0VKSGtpUmY1dW5tYmRNTDFkNGtkdmxHMkBjbGllbnRzIiwiYXVkIjoiL3BldHN0b3JlIiwiaWF0IjoxNTY5NTMyMTc4LCJleHAiOjE1Njk2MTg1NzgsImF6cCI6InFZTTZ5WTBvRUpIa2lSZjV1bm1jZE1MMWQ0a2R2bEcyIiwiZ3R5IjoiY2xpZW50LWNyZWRlbnRpYWxzIn0.obDoH14utNKOs2DWcPN_HlnmhcYlo94upQtwBZiEs903-vjRSrMt2ZPXwLq9ukxcmSH40TciPJIsKEyydt8Y9dOf2tqwNZC67pq8lPQ1MnvLhBAacg0cfykSwmgVl4nAzGYFX8s7wqBG3XdE6L4xgbPNtsgyyq6r0NnEK5oQyasi7GnKdlZE3-NJg1btGT7qVSD30aQFxIFVEFddeCWfwjb6w5dzuP0InIDF3J0e2EPGlX14q20tduBz-csbwNldjXPrK6PTmuNIXZwKjLeHdC85BGETrJmVFTgiXvYRKeFXp7t-zovdGg3ZPjbJl8f0tp0wB-rHrPbtkuI7a7gNBA'
# curl --verbose --silent \
#   --header "authorization: Bearer $TAMPERED_AUTH0_TOKEN" \
#   "$GLOO_PROXY_URL/api/pets"
http "$GLOO_PROXY_URL/api/pets" "authorization:Bearer $TAMPERED_AUTH0_TOKEN"
