#!/usr/bin/env bash
#
# Installs DataDog agents

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

if [[ -f "${HOME}/scripts/secret/glooe_license_key.sh" ]]; then
  # export GLOOE_LICENSE_KEY=<valid key>
  source "${HOME}/scripts/secret/glooe_license_key.sh"
fi

# Update Gloo Enterprise configuration for Datadog
kubectl create namespace "${GLOO_NAMESPACE}"

helm install glooe glooe/gloo-ee \
  --namespace="${GLOO_NAMESPACE}" \
  --version="${GLOO_VERSION}" \
  --set="license_key=${GLOOE_LICENSE_KEY}" \
  --values - <<EOF
gloo:
  gatewayProxies:
    gatewayProxy:
      podTemplate:
        extraAnnotations:
          ad.datadoghq.com/gateway-proxy.check_names: '["envoy"]'
          ad.datadoghq.com/gateway-proxy.init_configs: '[{}]'
          ad.datadoghq.com/gateway-proxy.instances: '[{"stats_url": "http://%%host%%:8082/stats"}]'
          ad.datadoghq.com/gateway-proxy.logs: '[{"source": "envoy", "service": "gateway-proxy"}]'
      readConfig: true
      tracing:
        cluster:
        - name: datadog_agent
          connect_timeout: 1s
          type: STRICT_DNS
          lb_policy: ROUND_ROBIN
          hosts:
          - socket_address:
              address: localhost
              port_value: 8126
        provider:
          name: envoy.tracers.datadog
          config:
            collector_cluster: datadog_agent
            service_name: envoy
EOF

# ad.datadoghq.com/gateway-proxy.instances: '[{"stats_url": "http://gateway-proxy.gloo-system.svc.cluster.local:80/stats"}]'

# Add Envoy stats route
# kubectl apply --filename - <<EOF
# apiVersion: gloo.solo.io/v1
# kind: Upstream
# metadata:
#   name: localhost
#   namespace: ${GLOO_NAMESPACE}
# spec:
#   static:
#     hosts:
#       - addr: localhost
#         port: 8082
# EOF

# glooctl add route \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}" \
#   --path-prefix='/stats' \
#   --dest-name='localhost' \
#   --dest-namespace="${GLOO_NAMESPACE}"

# glooctl add route \
#   --name='default' \
#   --namespace="${GLOO_NAMESPACE}" \
#   --path-prefix='/' \
#   --dest-name='default-petclinic-8080' \
#   --dest-namespace="${GLOO_NAMESPACE}"

# Create a secret that contains your API Key. This secret will be used in the manifest to deploy the Datadog Agent.
if [[ -f "${HOME}/scripts/secret/datadog_credentials.sh" ]]; then
  # Cleanup old resources
  kubectl delete \
    --ignore-not-found='true' \
    secret/datadog-secret

  # DATADOG_API_KEY='<access key>'
  source "${HOME}/scripts/secret/datadog_credentials.sh"

  kubectl create secret generic datadog-secret \
    --from-literal api-key="${DATADOG_API_KEY}"
fi

helm upgrade --install datadog stable/datadog \
  --set="datadog.apiKey=${DATADOG_API_KEY}" \
  --set='datadog.apiKeyExistingSecret=datadog-secret' \
  --set='datadog.nonLocalTraffic=true' \
  --set='datadog.logsEnabled=true' \
  --set='datadog.logsConfigContainerCollectAll=true' \
  --set='datadog.apmEnabled=true' \
  --set='datadog.processAgentEnabled=true' \
  --set='datadog.useHostPort=true'
