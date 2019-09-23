#!/usr/bin/env bash

# Based on GlooE Opa Authorization example
# https://gloo.solo.io/gloo_routing/virtual_services/security/opa/

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

# Install  example application
kubectl --namespace='default' apply \
  --filename="$SCRIPT_DIR/../resources/petstore.yaml"

# Create policy ConfigMap deleting any leftovers from other examples
POLICY_K8S_CONFIGMAP='allow-get-users'
kubectl --namespace='gloo-system' delete configmap "$POLICY_K8S_CONFIGMAP" && true # ignore errors
kubectl --namespace='gloo-system' create configmap "$POLICY_K8S_CONFIGMAP" --from-file="$SCRIPT_DIR/policy.rego"

# Cleanup old examples
kubectl --namespace='gloo-system' delete virtualservice default && true # ignore errors

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system' \
#   --enable-opa-auth \
#   --opa-query='data.test.allow == true' \
#   --opa-module-ref="gloo-system.$POLICY_K8S_CONFIGMAP"

# glooctl add route \
#   --name default \
#   --path-prefix='/' \
#   --dest-name='default-petstore-8080' \
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
            name: default-petstore-8080
            namespace: gloo-system
    virtualHostPlugins:
      extensions:
        configs:
          extauth:
            configs:
            - opa_auth:
                modules:
                - name: $POLICY_K8S_CONFIGMAP
                  namespace: gloo-system
                query: 'data.test.allow == true'
EOF

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

printf "Should return 403\n"
# curl --silent --write-out "%{http_code}\n" http://localhost:8080/api
http --headers http://localhost:8080/api

printf "Should return 403\n"
# curl --silent --write-out  "%{http_code}\n" --request DELETE http://localhost:8080/api/pets/1
http --headers DELETE http://localhost:8080/api/pets/1

printf "Should return 204\n"
# curl --silent --write-out "%{http_code}\n" --request DELETE http://localhost:8080/api/pets/2
http --headers DELETE http://localhost:8080/api/pets/2
