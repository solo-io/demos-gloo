#!/usr/bin/env bash

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
        regex: '/[a-z]{5}'
      directResponseAction:
        status: 200
        body: "Matched"
    - matcher:
        prefix: /
      directResponseAction:
        status: 200
        body: "Fail"
EOF

PROXY_PID_FILE="${SCRIPT_DIR}/proxy_pf.pid"
if [[ -f "${PROXY_PID_FILE}" ]]; then
  xargs kill <"${PROXY_PID_FILE}" && true # ignore errors
  rm "${PROXY_PID_FILE}"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
(
  (kubectl --namespace='gloo-system' port-forward deployment/gateway-proxy-v2 8080:8080 >/dev/null) &
  echo $! >"${PROXY_PID_FILE}" &
)

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould work\n"
curl "${PROXY_URL}/posts"
# http "${PROXY_URL}/api/calculation-engine/foo/read-request"

printf "\nShould work\n"
curl "${PROXY_URL}/api/calculation-engine/foo/read-request"
# http "${PROXY_URL}/api/calculation-engine/foo/read-request"

printf "\nShould work\n"
curl "${PROXY_URL}/api/calculation-engine/bar/read-request"
# http "${PROXY_URL}/api/calculation-engine/bar/read-request"

printf "\nShould Fail\n"
curl "${PROXY_URL}/api/calculation-nope/foo/read-request"
# http "${PROXY_URL}/api/calculation-nope/foo/read-request"
