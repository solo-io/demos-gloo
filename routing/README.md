# Solo.io Gloo Traffic Routing Examples

## Routing Overview

This directory includes a number of Gloo traffic routing examples.

These examples assume you are running a locally accessible Kubernetes cluster, i.e. `kubectl` can access the cluster. You can use the [`../start_cluster.sh`](../start_cluster.sh) to start a Kubernetes cluster.

All included `run_xxx_demo.sh` scripts are paired with a `cleanup_xxx_demo.sh` script that will remove all installed assets used by the demo.

## Examples

* `run_regex_demo.sh` - shows matching a request using a regular expression (regex) to enable routing requests to upstream services
