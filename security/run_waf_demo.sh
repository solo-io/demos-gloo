#!/usr/bin/env bash

# Based on GlooE WAF example
# https://gloo.solo.io/gloo_routing/gateway_configuration/waf/

# brew install kubernetes-cli httpie solo-io/tap/glooctl jq

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu

function print_error() {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line ${line} of file ${file}:" >&2
  sed "${line}q;d" "${file}" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/../working_environment.sh"

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

# Install example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system'

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
          waf:
            settings:
              ruleSets:
              - ruleStr: |
                  # Turn rule engine on
                  SecRuleEngine On
                  SecRule REQUEST_HEADERS:User-Agent "nikto" "id:107,phase:1,log,deny,t:lowercase,status:403,msg:'well-known port scanning tool'"
EOF

sleep 10

# kubectl --namespace='gloo-system' get virtualservice/default --output yaml

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# Turn on Gloo proxy debug logging
kubectl --namespace='gloo-system' port-forward deployment/gateway-proxy-v2 19000 >/dev/null 2>&1 &
sleep 2
PID=$!
# curl localhost:19000/logging?level=debug --request POST >/dev/null
http POST localhost:19000/logging level==debug >/dev/null
kill "$PID"

# Create a background proxy log scrapper
LOGGER_PID_FILE="${SCRIPT_DIR}/logger.pid"
if [[ -f "${LOGGER_PID_FILE}" ]]; then
  xargs kill <"${LOGGER_PID_FILE}" && true # ignore errors
  rm "${LOGGER_PID_FILE}" "${SCRIPT_DIR}/proxy.log"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true' # wait for Gloo proxy to be fully running
(
  (kubectl --namespace='gloo-system' logs --follow=true deployment/gateway-proxy-v2 >"${SCRIPT_DIR}/proxy.log") &
  echo $! >"${LOGGER_PID_FILE}" &
)

# Port forward the Gloo proxy to a localhost port
PROXY_PID_FILE="${SCRIPT_DIR}/proxy_pf.pid"
if [[ -f "${PROXY_PID_FILE}" ]]; then
  xargs kill <"${PROXY_PID_FILE}" && true # ignore errors
  rm "${PROXY_PID_FILE}"
fi
# kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true' # wait for Gloo proxy to be fully running
(
  (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) &
  echo $! >"${PROXY_PID_FILE}" &
)

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

sleep 10

printf "\nShould return 200 OK\n"
# curl --silent --write-out "\n%{http_code}\n" "${PROXY_URL}/api/pets/1"
http "${PROXY_URL}/api/pets/1"

# Rule 107
printf "\nShould return 403 Forbidden\n"
# curl --silent --write-out "\n%{http_code}\n" --header "User-Agent: Nikto" "${PROXY_URL}/api/pets/1"
http "${PROXY_URL}/api/pets/1" 'User-Agent:Nikto'

printf "\nShould return 200 OK\n"
# curl --silent --write-out "\n%{http_code}\n" --header "User-Agent: Scott" "${PROXY_URL}/api/pets/1"
http "${PROXY_URL}/api/pets/1" 'User-Agent:Scott'
