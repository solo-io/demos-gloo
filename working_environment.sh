#!/usr/bin/env bash
# shellcheck disable=SC2034

K8S_TOOL='minikube' # kind, minikube, minishift, gcloud, custom
GLOO_MODE='ent'     # oss, ent, knative, none

GLOO_NAMESPACE='gloo-system'

GLOO_VERSION='1.2.0' # ent
# GLOO_VERSION='1.2.12' # oss

GLOO_DEMO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Create absolute path reference to top level directory of this demo repo
# GLOO_DEMO_RESOURCES_HOME='https://raw.githubusercontent.com/solo-io/demos-gloo/master/resources'
GLOO_DEMO_RESOURCES_HOME=${GLOO_DEMO_RESOURCES_HOME:-"${GLOO_DEMO_HOME}/resources"}
