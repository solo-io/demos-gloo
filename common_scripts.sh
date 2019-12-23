#!/usr/bin/env bash
# shellcheck disable=SC2034

function print_error() {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line ${line} of file ${file}:" >&2
  sed "${line}q;d" "${file}" >&2
}

function wait_for_k8s_metrics_server() {
  # Hack to deal with delay in gcloud and other k8s clusters not starting
  # metrics server fast enough for helm
  PID_FILE="${SCRIPT_DIR}/k8s_proxy.pid"
  if [[ -f "${PID_FILE}" ]]; then
    xargs kill <"${PID_FILE}" && true # ignore errors
    rm "${PID_FILE}"
  fi

  kubectl proxy --port 8001 >/dev/null &
  echo $! >"${PID_FILE}"

  sleep 2

  until curl --output /dev/null --silent --fail 'http://localhost:8001/apis/metrics.k8s.io/v1beta1/'; do
    echo 'Waiting for availability of Kubernetes metrics API needed for Helm...'
    sleep 5
  done

  xargs kill <"${PID_FILE}" && true # ignore errors
  rm "${PID_FILE}"
}

# Creates k8s port-foward in background and tracks background process pid
# Parameters
# - Namespace
# - Name
# - Port
function port_forward_deployment() {
  NAMESPACE=$1
  NAME=$2
  PORT=$3

  cleanup_port_forward_deployment "${NAME}"

  kubectl --namespace="${NAMESPACE}" rollout status deployment/"${NAME}" --watch='true'
  kubectl --namespace="${NAMESPACE}" port-forward deployment/"${NAME}" "${PORT}" >/dev/null &
  echo $! >"${PID_FILE}"
}

# Deletes background port-forward
# Parameters
# - Name
function cleanup_port_forward_deployment() {
  NAME=$1

  PID_FILE="${SCRIPT_DIR}/${NAME}_pf.pid"
  if [[ -f "${PID_FILE}" ]]; then
    xargs kill <"${PID_FILE}" && true # ignore errors
    rm "${PID_FILE}"
  fi
}

function set_gloo_proxy_log_level() {
  DEBUG_LEVEL="${1:-debug}"

  kubectl --namespace="${GLOO_NAMESPACE:-gloo-system}" rollout status deployment/gateway-proxy --watch='true'
  kubectl --namespace="${GLOO_NAMESPACE:-gloo-system}" port-forward deployment/gateway-proxy 19000 >/dev/null 2>&1 &
  PID=$!

  curl --silent --request POST "http://localhost:19000/logging?level=${DEBUG_LEVEL}" >/dev/null

  kill "${PID}"
}
