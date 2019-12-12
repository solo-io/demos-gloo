# Solo.io Gloo Enterprise Envoy Demos

## Overview

This repository contains a number of demos of Solo.io Gloo Enterprise Envoy capabilities. These demos are designed to run on any Kubernetes cluster 1.11 or newer. Gloo can also run off Kubernetes and that is demonstrated through very similar scripts. These included scripts are designed to be self-contained including a number of test client requests. These scripts are intended to be both educational of Gloo capabilities and to provide starting points for your own exploration of Gloo.

These scripts have been heavily test on macOS, and should work on any operating system with BASH shell support.

## Pre-requisites

* If using include [`start_cluster.sh`](start_cluster.sh) script one of the following Kubernetes environments: `minikube`, `kind`, `minishift`, OpenShift, Google GKE
* `helm` or `glooctl` to install Gloo Enterprise, and a valid (Trial) Gloo Enterprise License
* `kubectl`
* `curl` or `httpie`

Some *nix utilities like `base64` (`brew install base64` or `brew install coreutils`)

Some scripts also use `jq` to help parse responses to make them more human friendly

All scripts assume you've made a local copy of this repository (`git clone`) as there are some assumptions about directory hierarchy.

## Running

Check the environment variable settings in [`working_environment.sh`](working_environment.sh) to ensure they match you're environment

[`start_cluster.sh`](start_cluster.sh) will start a Kubernetes cluster and install Gloo based on the settings in [`working_environment.sh`](working_environment.sh). [`stop_cluster.sh`](stop_cluster.sh) will shutdown the Kubernetes cluster created by [`start_cluster.sh`](start_cluster.sh).

In the included directories there are a number of `run_xxx_demo.sh` scripts that you can run once you have a running and accessible Kubernetes cluster. Accessible means that calls to `kubectl` will correctly access your target cluster. There are matched `cleanup_xxx_demo.sh` scripts that will remove all deployed images and manifests used by associated demo. The cleanup scripts may also kill background process the run scripts created specially for `kubectl port-forward` processes. The background processes are tracked through `*.pid` files created by the run scripts.

These examples may use a number of example Kubernetes services whose manifests are located in the [`resources`](resources/) directory.

## Staying in Touch

* Join our [Solo.io Slack community](slack.solo.io)

## Helpful Gloo Debugging Commands

### Get Gloo gateway proxy information

```shell
kubectl --namespace gloo-system deployment/gateway-proxy 19000
http://localhost:19000
```

### Change log level

```shell
kubectl --namespace='gloo-system' port-forward deployment/gateway-proxy 19000 &
PROXY_PID=$!
sleep 2
curl --request POST 'http://localhost:19000/logging?level=debug'
kill ${PROXY_PID}
```

### Check configuration

```shell
glooctl check
```

### Get Gloo logs

```shell
glooctl proxy logs
```
