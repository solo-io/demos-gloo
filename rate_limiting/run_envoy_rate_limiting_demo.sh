#!/usr/bin/env bash

# Based on GlooE Rate Limiting example
# https://gloo.solo.io/gloo_routing/virtual_services/rate_limiting/envoy/

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

if [[ $K8S_TOOL == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete virtualservice/default && true # ignore errors

kubectl --namespace='gloo-system' patch settings/default \
  --type='json' \
  --patch='[
    {
      "op": "remove",
      "path": "/spec/extensions/configs/envoy-rate-limit"
    }
  ]' && true #ignore errors

# Install Petclinic example application
kubectl --namespace='default' apply \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petstore.yaml"

# glooctl edit settings ratelimit custom-server-config --name default

# descriptors:
# - key: account_id
#   descriptors:
#   - key: plan
#     value: BASIC
#     rateLimit:
#       requestsPerUnit: 1
#       unit: MINUTE
#   - key: plan
#     value: PLUS
#     rateLimit:
#       requestsPerUnit: 20
#       unit: MINUTE

kubectl --namespace='gloo-system' patch settings/default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  extensions:
    configs:
      envoy-rate-limit:
        customConfig:
          descriptors:
          - key: account_id
            descriptors:
            - key: plan
              value: BASIC
              rateLimit:
                requestsPerUnit: 1
                unit: MINUTE
            - key: plan
              value: PLUS
              rateLimit:
                requestsPerUnit: 3
                unit: MINUTE
EOF
)"

# kubectl --namespace='gloo-system' get settings/default --output yaml

# glooctl add route \
#   --name='default' \
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
          envoy-rate-limit:
            rateLimits:
            - actions:
              - requestHeaders:
                  descriptorKey: account_id
                  headerName: x-account-id
              - requestHeaders:
                  descriptorKey: plan
                  headerName: x-plan
EOF

PROXY_PID_FILE="$SCRIPT_DIR/proxy_pf.pid"
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

sleep 5

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nPlans:\n* BASIC - 1 call per minute per account_id\n* PLUS  - 3 calls per minute per account_id\n\n"

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NORMAL=$(tput sgr0)

for PLAN in  BASIC PLUS; do
  case $PLAN in
  BASIC) cp="${RED}BASIC${NORMAL}" ;;
  PLUS ) cp="${GREEN}PLUS${NORMAL}" ;;
  esac

  for ACCOUNT in {1..3}; do
    ca="$(tput setaf $ACCOUNT)${ACCOUNT}${NORMAL}"

    for i in {1..5}; do
      ci="$(tput setaf $i)${i}${NORMAL}"

      STATUS=$(curl --silent --write-out "%{http_code}" --output /dev/null \
        --header "x-account-id: $ACCOUNT" \
        --header "x-plan: $PLAN" \
        "${PROXY_URL:-http://localhost:8080}/api/pets/1"
      )
      case $STATUS in
      200) STATUS="${GREEN}200 OK${NORMAL}" ;;
      429) STATUS="${YELLOW}429 Too Many Requests${NORMAL}" ;;
      *  ) STATUS="${RED}${STATUS}${NORMAL}" ;;
      esac

      printf "Call %s; Account %s; Plan %16s; Status: %s\n" "$ci" "$ca" "$cp" "$STATUS"
    done
    printf "\n"
  done
done
