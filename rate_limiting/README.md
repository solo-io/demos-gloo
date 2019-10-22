# Solo.io Gloo Rate Limiting Examples

## Overview

This directory includes a number of Gloo Rate Limiting examples.

These examples assume you are running a locally accessible Kubernetes cluster, i.e. `kubectl` can access the cluster. You can use the [`../start_cluster.sh`](../start_cluster.sh) to start a Kubernetes cluster.

All included `run_xxx_demo.sh` scripts are paired with a `cleanup_xxx_demo.sh` script that will remove all installed assets used by the demo.

## Examples

* `run_gloo_rate_limiting_demo.sh` - shows uses Gloo's Rate Limiting abstraction to throttle authenticated and non-authenticated requests
* `run_envoy_rate_limiting_demo.sh` - shows uses full Enovy Rate Limiting abstraction to requests requests
