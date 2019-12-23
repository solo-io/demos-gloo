#!/usr/bin/env bash

# Based on GlooE Opa Authorization example
# https://gloo.solo.io/gloo_routing/virtual_services/security/opa/

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../../common_scripts.sh"
source "${SCRIPT_DIR}/../../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

POLICY_K8S_CONFIGMAP='allow-get-users'

# Cleanup previous example runs
kubectl --namespace="${GLOO_NAMESPACE}" delete \
  --ignore-not-found='true' \
  virtualservice/default \
  authconfig/my-opa \
  configmap/"${POLICY_K8S_CONFIGMAP}"

kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Install example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Create policy ConfigMap
kubectl --namespace="${GLOO_NAMESPACE}" create configmap "${POLICY_K8S_CONFIGMAP}" \
  --from-file="${SCRIPT_DIR}/policy.rego"

kubectl apply --filename - <<EOF
apiVersion: enterprise.gloo.solo.io/v1
kind: AuthConfig
metadata:
  name: my-opa
  namespace: "${GLOO_NAMESPACE}"
spec:
  configs:
  - opa_auth:
      modules:
      - name: ${POLICY_K8S_CONFIGMAP}
        namespace: "${GLOO_NAMESPACE}"
      query: 'data.test.allow == true'
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
      extauth:
        config_ref:
          name: my-opa
          namespace: "${GLOO_NAMESPACE}"
EOF

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment "${GLOO_NAMESPACE}" 'gateway-proxy' '8080'

sleep 5

printf "Should return 403\n"
# curl --silent --write-out "%{http_code}\n" --request GET 'http://localhost:8080/api'
http --headers GET 'http://localhost:8080/api'

printf "Should return 403\n"
# curl --silent --write-out  "%{http_code}\n" --request DELETE 'http://localhost:8080/api/pets/1'
http --headers DELETE 'http://localhost:8080/api/pets/1'

printf "Should return 200\n"
# curl --silent --write-out "%{http_code}\n" --request GET 'http://localhost:8080/api/pets/2'
http --headers GET 'http://localhost:8080/api/pets/2'

printf "Should return 204\n"
# curl --silent --write-out "%{http_code}\n" --request DELETE 'http://localhost:8080/api/pets/2'
http --headers DELETE 'http://localhost:8080/api/pets/2'
