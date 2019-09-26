#!/usr/bin/env bash
# shellcheck disable=SC2034

K8S_TOOL=kind       # kind, minikube, minishift, gcloud
TILLER_MODE=cluster # local or cluster
GLOO_MODE=ent       # oss, ent, knative

GLOO_VERSION=0.18.32 # ent

# Create absolute path reference to top level directory of this demo repo
# GLOO_DEMO_HOME=https://raw.githubusercontent.com/sololabs/demos2/resources
GLOO_DEMO_RESOURCES_HOME=${GLOO_DEMO_HOME:-"$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/resources"}
