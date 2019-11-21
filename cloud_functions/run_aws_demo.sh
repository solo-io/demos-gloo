#!/usr/bin/env bash

FUNCTION_SECRET_NAME='my-function-secret'
FUNCTION_UPSTREAM_NAME='my-function-upstream'

AWS_REGION='us-east-1'
AWS_FUNCTION_NAME='hello-world'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

# Configure Credentials
if [[ -f "${HOME}/scripts/secret/aws_function_credentials.sh" ]]; then
  # export AWS_ACCESS_KEY=
  # export AWS_SECRET_KEY=
  source "${HOME}/scripts/secret/aws_function_credentials.sh"
fi

if [[ -z "${AWS_ACCESS_KEY}" ]] || [[ -z "${AWS_SECRET_KEY}" ]]; then
  echo 'Must set AWS environment variables'
  exit
fi

# Cleanup old examples
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  secret/"${FUNCTION_SECRET_NAME}" \
  upstream/"${FUNCTION_UPSTREAM_NAME}"

# Create secret for AWS Function

# glooctl create secret aws \
#   --name="${FUNCTION_SECRET_NAME}" \
#   --namespace='gloo-system' \
#   --access-key="${AWS_ACCESS_KEY}" \
#   --secret-key="${AWS_SECRET_KEY}"

kubectl apply --filename - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: ${FUNCTION_SECRET_NAME}
  namespace: gloo-system
data:
  aws_access_key_id: $(base64 --wrap=0 <(echo -n "${AWS_ACCESS_KEY}"))
  aws_secret_access_key: $(base64 --wrap=0 <(echo -n "${AWS_SECRET_KEY}"))
EOF

# Create Gloo upstream for function.
# This example assumes an API Gateway function

# glooctl create upstream aws \
#   --name="${FUNCTION_UPSTREAM_NAME}" \
#   --namespace='gloo-system' \
#   --aws-region="${AWS_REGION}" \
#   --aws-secret-name="${FUNCTION_SECRET_NAME}" \
#   --aws-secret-namespace='gloo-system'

kubectl apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: ${FUNCTION_UPSTREAM_NAME}
  namespace: gloo-system
spec:
  upstreamSpec:
    aws:
      region: ${AWS_REGION}
      secretRef:
        name: ${FUNCTION_SECRET_NAME}
        namespace: gloo-system
EOF

# Create a Virtual Service referencing Azure upstream/function

# glooctl add route \
#   --name='default' \
#   --namespace='gloo-system' \
#   --path-prefix='/helloaws' \
#   --dest-name="${FUNCTION_UPSTREAM_NAME}" \
#   --aws-function-name="${AWS_FUNCTION_NAME}"

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
    - matcher:
        prefix: /helloaws
      routeAction:
        single:
          destinationSpec:
            aws:
              logicalName: ${AWS_FUNCTION_NAME}
          upstream:
            name: ${FUNCTION_UPSTREAM_NAME}
            namespace: gloo-system
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

curl --silent "${PROXY_URL}/helloaws" | jq --raw-output '.body'
