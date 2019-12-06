#!/usr/bin/env bash

FUNCTION_SECRET_NAME='my-function-secret'
FUNCTION_UPSTREAM_NAME='my-function-upstream'

# AZURE_APP_NAME='azure app name'
# AZURE_FUNCTION_NAME='azure function name'
# AZURE_MASTER_HOST_KEY_VALUE='_master host key value'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Configure Credentials
if [[ -f "${HOME}/scripts/secret/azure_function_credentials.sh" ]]; then
  # export AZURE_APP_NAME='azure app name'
  # export AZURE_FUNCTION_NAME='azure function name'
  # export AZURE_MASTER_HOST_KEY_VALUE='_master host key value'
  source "${HOME}/scripts/secret/azure_function_credentials.sh"
fi

if [[ -z "${AZURE_APP_NAME}" ]] ||
  [[ -z "${AZURE_FUNCTION_NAME}" ]] ||
  [[ -z "${AZURE_MASTER_HOST_KEY_VALUE}" ]]; then
  echo 'Must set Azure environment variables'
  exit
fi

# Cleanup old examples
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${FUNCTION_SECRET_NAME}" \
  upstream/"${FUNCTION_UPSTREAM_NAME}"

# Create secret for Azure Function Host Key '_master'

# glooctl create secret azure \
#   --name="${FUNCTION_SECRET_NAME}" \
#   --namespace='gloo-system' \
#   --api-keys="_master=${AZURE_MASTER_HOST_KEY_VALUE}"

kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  annotations:
    resource_kind: '*v1.Secret'
  name: ${FUNCTION_SECRET_NAME}
  namespace: gloo-system
data:
  azure: $(base64 --wrap=0 <<EOF2
apiKeys:
  _master: ${AZURE_MASTER_HOST_KEY_VALUE}
EOF2
)
EOF

# Create Gloo upstream for Azure function.
# This example assumes an HTTP Trigger function that takes a single 'name' parameter

# glooctl create upstream azure \
#   --name="${FUNCTION_UPSTREAM_NAME}" \
#   --namespace='gloo-system' \
#   --azure-app-name="${AZURE_APP_NAME}" \
#   --azure-secret-name="${FUNCTION_SECRET_NAME}" \
#   --azure-secret-namespace='gloo-system'

kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: ${FUNCTION_UPSTREAM_NAME}
  namespace: gloo-system
spec:
  upstreamSpec:
    azure:
      functionAppName: ${AZURE_APP_NAME}
      functions:
      - functionName: ${AZURE_FUNCTION_NAME}
        authLevel: Function
      secretRef:
        name: ${FUNCTION_SECRET_NAME}
        namespace: gloo-system
EOF

# Create a Virtual Service referencing Azure upstream/function

# glooctl add route \
#   --name='default' \
#   --namespace='gloo-system' \
#   --path-prefix='/helloazure' \
#   --dest-name="${FUNCTION_UPSTREAM_NAME}" \
#   --azure-function-name="${AZURE_FUNCTION_NAME}"

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    routes:
    - matchers:
      - prefix: /helloazure
      routeAction:
        single:
          destinationSpec:
            azure:
              functionName: ${AZURE_FUNCTION_NAME}
          upstream:
            name: ${FUNCTION_UPSTREAM_NAME}
            namespace: gloo-system
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

curl --data '{"name":"Scott"}' --header "Content-Type: application/json" --request POST "${PROXY_URL}/helloazure"
