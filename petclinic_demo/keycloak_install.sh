#!/usr/bin/env bash

KEYCLOAK_NAMESPACE='keycloak'

# Get directory this script is located in to access script local files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

source "${SCRIPT_DIR}/../common_scripts.sh"
source "${SCRIPT_DIR}/../working_environment.sh"

# Will exit script if we would use an uninitialised variable (nounset) or when a
# simple command (not a control structure) fails (errexit)
set -eu
trap print_error ERR

kubectl create namespace "${KEYCLOAK_NAMESPACE}" && true # ignore errors

kubectl --namespace="${KEYCLOAK_NAMESPACE}" delete \
  --ignore-not-found='true' \
  secret/realm-secret

kubectl create secret generic realm-secret \
  --namespace="${KEYCLOAK_NAMESPACE}" \
  --from-file="${SCRIPT_DIR}/realm.json"

helm repo add codecentric https://codecentric.github.io/helm-charts
helm upgrade --install keycloak codecentric/keycloak \
  --namespace="${KEYCLOAK_NAMESPACE}" \
  --version='6.1.0' \
  --values - <<EOF
keycloak:
  extraVolumes: |
    - name: realm-secret
      secret:
        secretName: realm-secret

  extraVolumeMounts: |
    - name: realm-secret
      mountPath: "/realm/"
      readOnly: true

  extraArgs: -Dkeycloak.import=/realm/realm.json

  password: password

  ## Ingress configuration.
  ## ref: https://kubernetes.io/docs/user-guide/ingress/
  ingress:
    enabled: true
    path: /

    annotations:
      kubernetes.io/ingress.class: nginx
      kubernetes.io/tls-acme: "true"
      ingress.kubernetes.io/affinity: cookie

    ## List of hosts for the ingress
    hosts:
      - keycloak.example.test
EOF
