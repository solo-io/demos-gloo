# Solo.io Gloo Traffic Routing Examples

## Routing Overview

This directory includes a number of Gloo traffic routing examples.

These examples assume you are running a locally accessible Kubernetes cluster, i.e. `kubectl` can access the cluster. You can use the [`../start_cluster.sh`](../start_cluster.sh) to start a Kubernetes cluster.

All demos can be cleaned up using the [`cleanup_demo.sh`](cleanup_demo.sh) script.

## Examples

* [`run_regex_demo.sh`](run_regex_demo.sh) - shows matching a request using a regular expression (regex) to enable routing requests to upstream services
* [`run_header_demo.sh`](run_header_demo.sh) - shows matching a request using header value matching to enable routing requests to upstream services
* [`run_rewrite_demo.sh`](run_rewrite_demo.sh) - shows prefix rewriting to help map one query path to another that the upstream is expecting, e.g. `/foo/api` => `/api`
* [`run_ingress_demo.sh`](run_ingress_demo.sh) - shows Gloo using Kubernetes Ingress resources to specify the route
* [`run_delegation_demo.sh`](run_delegation_demo.sh) - shows how to break query path matching into separate manifests to allow for delegated management of request to updates mappings.

