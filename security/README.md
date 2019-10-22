# Solo.io Gloo Security Examples

## Security Overview

This directory includes a number of Gloo security examples including Authentication, Authorization, Web Application Firewall, and mTLS.

These examples assume you are running a locally accessible Kubernetes cluster, i.e. `kubectl` can access the cluster. You can use the [`../start_cluster.sh`](../start_cluster.sh) to start a Kubernetes cluster.

All included `run_xxx_demo.sh` scripts are paired with a `cleanup_xxx_demo.sh` script that will remove all installed assets used by the demo.

## Examples

### Authentication

* `run_auth0_demo.sh` - shows OAuth Client Credential flow using the Auth0 SaaS
* `run_oidc_dex_demo.sh` - shows using OpenID Connect (OIDC) with DEX provider
* `run_oidc_google_demo.sh` - shows using OpenID Connect (OIDC) with Google provider

### Authorization

* `run_opa_authz_demo.sh` - shows using Open Policy Agent (OPA) to authorize runtime requests

### Web Application Firewall (WAF)

* `run_waf_demo.sh` - shows using Gloo's integration of ModSecurity to act as a WAF

### Security integration

* `run_istio_mtls_demo.sh` - shows Gloo coordination with Istio SDS to enable mTLS between Gloo proxy(s) and upstream services protected by Istio sidecars
