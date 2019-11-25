#!/usr/bin/env bash

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

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
      - prefix: /
        headers:
        - name: header1
          value: value1
      directResponseAction:
        status: 200
        body: "Matched static"
    - matchers:
      - prefix: /
        headers:
        - name: header3
      directResponseAction:
        status: 200
        body: "Matched static any value"
    - matchers:
      - prefix: /
        headers:
        - name: header2
          regex: true
          value: "value[0-9]{1}"
      directResponseAction:
        status: 200
        body: "Matched regex"
    - matchers:
      - prefix: /
        headers:
        - name: header4
          invertMatch: true
        - name: header5
      directResponseAction:
        status: 200
        body: "Matched static no header4"
    - matchers:
      - prefix: /
      directResponseAction:
        status: 200
        body: "Fail"
EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy-v2' '8080'

sleep 2

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould work\n"
curl --write-out '\n%{http_code}' --header "header1: value1" "${PROXY_URL}/"

printf "\n\nShould fail\n"
curl --write-out '\n%{http_code}' --header "header1: value2" "${PROXY_URL}/"

printf "\n\nShould work\n"
curl --write-out '\n%{http_code}' --header "header2: value5" "${PROXY_URL}/"

printf "\n\nShould fail\n"
curl --write-out '\n%{http_code}' --header "header2: valueA" "${PROXY_URL}/"

printf "\n\nShould work\n"
curl --write-out '\n%{http_code}' --header "header3: qewr23542" "${PROXY_URL}/"

printf "\n\nShould work\n"
curl --write-out '\n%{http_code}' --header "header5: qewr23542" "${PROXY_URL}/"

printf "\n\nShould fail\n"
curl --write-out '\n%{http_code}' --header "header4: qewr23542" --header "header5: qewr23542" "${PROXY_URL}/"

printf "\n\nShould fail\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/"
