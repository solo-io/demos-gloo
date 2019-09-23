#!/usr/bin/env bash

# Based on GlooE OPA and OIDC example
# https://gloo.solo.io/gloo_routing/virtual_services/security/opa/#open-policy-agent-and-open-id-connect

# OIDC Configuration

OIDC_CLIENT_ID='gloo'
OIDC_CLIENT_SECRET='secretvalue'

OIDC_ISSUER_URL='http://dex.gloo-system.svc.cluster.local:32000/'
OIDC_APP_URL='http://localhost:8080/'
OIDC_CALLBACK_PATH='/callback'

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

# Install DEX OIDC Provider https://github.com/dexidp/dex
# DEX is not required for Gloo extauth; it is here as an OIDC provider to simplify example
helm upgrade --install dex stable/dex \
  --namespace='gloo-system' \
  --wait \
  --values - <<EOF
config:
  issuer: http://dex.gloo-system.svc.cluster.local:32000

  staticClients:
  - id: $OIDC_CLIENT_ID
    redirectURIs:
    - 'http://localhost:8080/callback'
    name: 'GlooApp'
    secret: $OIDC_CLIENT_SECRET

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

# Create policy ConfigMap deleting any leftovers from other examples
POLICY_K8S_CONFIGMAP='allow-jwt'
kubectl --namespace='gloo-system' delete configmap "$POLICY_K8S_CONFIGMAP" && true # ignore errors
kubectl --namespace='gloo-system' create configmap "$POLICY_K8S_CONFIGMAP" --from-file="$SCRIPT_DIR/allow-jwt.rego"

kubectl --namespace='gloo-system' rollout status deployment/dex --watch='true'

# Start a couple of port-forwards to allow DEX OIDC Provider to work with Gloo
# Use some Bash magic to keep these scripts re-entrant
DEX_PID_FILE=$SCRIPT_DIR/dex_pf.pid
if [[ -f $DEX_PID_FILE ]]; then
  xargs kill <"$DEX_PID_FILE" && true # ignore errors
  rm "$DEX_PID_FILE"
fi
( (kubectl --namespace='gloo-system' port-forward service/dex 32000:32000 >/dev/null) & echo $! > "$DEX_PID_FILE" & )

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="$SCRIPT_DIR/../resources/petclinic-db.yaml" \
  --filename="$SCRIPT_DIR/../resources/petclinic.yaml"

# Cleanup old examples
kubectl --namespace='gloo-system' delete virtualservice default && true # ignore errors

K8S_SECRET_NAME=my-oauth-secret

# glooctl create secret oauth \
#   --name="$K8S_SECRET_NAME" \
#   --namespace='gloo-system' \
#   --client-secret="$OIDC_CLIENT_SECRET"

kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  annotations:
    resource_kind: '*v1.Secret'
  name: $K8S_SECRET_NAME
  namespace: gloo-system
data:
  extension: $(base64 <<EOF2
config:
  client_secret: $OIDC_CLIENT_SECRET
EOF2
)
EOF

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system' \
#   --enable-oidc-auth \
#   --oidc-auth-app-url="$OIDC_APP_URL" \
#   --oidc-auth-callback-path="$OIDC_CALLBACK_PATH" \
#   --oidc-auth-client-id="$OIDC_CLIENT_ID" \
#   --oidc-auth-client-secret-name="$K8S_SECRET_NAME" \
#   --oidc-auth-client-secret-namespace='gloo-system' \
#   --oidc-auth-issuer-url="$OIDC_ISSUER_URL" \
#   --oidc-scope='email' \
#   --enable-opa-auth \
#   --opa-query='data.test.allow == true' \
#   --opa-module-ref="gloo-system.$POLICY_K8S_CONFIGMAP"

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
                app_url: $OIDC_APP_URL
                callback_path: $OIDC_CALLBACK_PATH
                client_id: $OIDC_CLIENT_ID
                client_secret_ref:
                  name: $K8S_SECRET_NAME
                  namespace: gloo-system
                issuer_url: $OIDC_ISSUER_URL
                scopes:
                - email
            - opa_auth:
                modules:
                - name: $POLICY_K8S_CONFIGMAP
                  namespace: gloo-system
                query: data.test.allow == true
EOF

# kubectl --namespace gloo-system get virtualservice/default --output yaml

kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petclinic --watch='true'

# open http://localhost:8080/
open -a "Google Chrome" --new --args --incognito "http://localhost:8080/"
