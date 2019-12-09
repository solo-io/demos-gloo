#!/usr/bin/env bash

# Based on GlooE Rate Limiting example
# https://gloo.solo.io/gloo_routing/virtual_services/rate_limiting/envoy/

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default

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
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

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
    - matchers:
      - prefix: /
      routeAction:
        single:
          upstream:
            name: default-petstore-8080
            namespace: gloo-system
    options:
      extensions:
        configs:
          rateLimitVhostExtension:
            rateLimits:
            - actions:
              - requestHeaders:
                  descriptorKey: account_id
                  headerName: x-account-id
              - requestHeaders:
                  descriptorKey: plan
                  headerName: x-plan
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

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
