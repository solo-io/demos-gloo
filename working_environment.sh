#!/usr/bin/env bash
# shellcheck disable=SC2034

K8S_TOOL=gcloud     # kind, minikube, minishift, gcloud
TILLER_MODE=cluster # local or cluster
GLOO_MODE=ent       # oss, ent, knative

GLOO_VERSION=0.18.31 # ent
