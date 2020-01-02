#!/usr/bin/env bash

# Based on https://docs.solo.io/gloo/latest/gloo_routing/virtual_services/delegation/

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
      - prefix: '/a'
      delegateAction:
        name: a-routes
        namespace: gloo-system
    - matchers:
      - prefix: '/b'
      delegateAction:
        name: b-routes
        namespace: gloo-system
    - matchers:
      - prefix: '/c'
      directResponseAction:
        status: 200
        body: "Success: Top Level - /c"
EOF

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: RouteTable
metadata:
  name: a-routes
  namespace: gloo-system
spec:
  routes:
  # the path matchers in this RouteTable must begin with the prefix '/a'
  - matchers:
    - prefix: '/a/1'
    directResponseAction:
      status: 200
      body: "Success: Delegated /a - /a/1"
  - matchers:
    - prefix: '/a/2'
    directResponseAction:
      status: 200
      body: "Success: Delegated /a - /a/2"
EOF

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: RouteTable
metadata:
  name: b-routes
  namespace: gloo-system
spec:
  routes:
  # the path matchers in this RouteTable must begin with the prefix '/b'
  - matchers:
    - prefix: '/b/1'
    directResponseAction:
      status: 200
      body: "Success: Delegated /b - /b/1"
  - matchers:
    - prefix: '/b/2'
    delegateAction:
      name: b2-routes
      namespace: gloo-system
EOF

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: RouteTable
metadata:
  name: b2-routes
  namespace: gloo-system
spec:
  routes:
  # the path matchers in this RouteTable must begin with the prefix '/b/2'
  - matchers:
    - prefix: '/b/2/foo'
    directResponseAction:
      status: 200
      body: "Success: Delegated /b/2 - /b/2/foo"
  - matchers:
    - prefix: '/b/2'
    directResponseAction:
      status: 200
      body: "Success: Delegated /b/2 - /b/2"
EOF

# You can use Kubernetes RBAC to manage access to the individual RouteTables and VirtualServices

# kubectl apply --filename - <<EOF
# apiVersion: rbac.authorization.k8s.io/v1
# kind: Role
# metadata:
#   namespace: gloo-system
#   name: b-route-edit
# rules:
# - apiGroups: ["gateway.solo.io"]
#   resources: ["RouteTable"]
#   resourceNames: ["b-routes"]
#   verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# ---
# apiVersion: rbac.authorization.k8s.io/v1
# kind: Role
# metadata:
#   namespace: gloo-system
#   name: b-route-view
# rules:
# - apiGroups: ["gateway.solo.io"]
#   resources: ["RouteTable"]
#   resourceNames: ["b-routes"]
#   verbs: ["get", "list", "watch"]
# EOF

# Create localhost port-forward of Gloo Proxy as this works with kind and other Kubernetes clusters
port_forward_deployment 'gloo-system' 'gateway-proxy' '8080'

sleep 5

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/a/1"

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/a/2"

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/b/1"

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/b/2"

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/b/2/foo"

printf "\nShould work\n"
curl --write-out '\n%{http_code}' "${PROXY_URL}/c/1"
