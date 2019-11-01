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

if [[ "${K8S_TOOL}" == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

POLICY_K8S_CONFIGMAP='allow-get-users'

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete \
  --ignore-not-found='true' \
  virtualservice/default \
  configmap/"${POLICY_K8S_CONFIGMAP}"
kubectl --namespace='default' delete \
  --ignore-not-found='true' \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Install  example application
kubectl --namespace='default' apply \
  --filename="${GLOO_DEMO_RESOURCES_HOME}/petstore.yaml"

# Create policy ConfigMap
kubectl --namespace='gloo-system' create configmap "${POLICY_K8S_CONFIGMAP}" \
  --from-file="${SCRIPT_DIR}/policy.rego"

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system' \
#   --enable-opa-auth \
#   --opa-query='data.test.allow == true' \
#   --opa-module-ref="gloo-system.${POLICY_K8S_CONFIGMAP}"

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
                - name: ${POLICY_K8S_CONFIGMAP}
                  namespace: gloo-system
                query: 'data.test.allow == true'
EOF

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

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
