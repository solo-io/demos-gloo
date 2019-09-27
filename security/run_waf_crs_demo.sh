#!/usr/bin/env bash

# Based on GlooE WAF example
# https://gloo.solo.io/gloo_routing/gateway_configuration/waf/

# brew install kubernetes-cli httpie solo-io/tap/glooctl jq

# Will exit script if we would use an uninitialised variable:
set -o nounset
# Will exit script when a simple command (not a control structure) fails:
set -o errexit

function print_error {
  read -r line file <<<"$(caller)"
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source "$SCRIPT_DIR/../working_environment.sh"

if [[ $K8S_TOOL == 'kind' ]]; then
  KUBECONFIG=$(kind get kubeconfig-path --name="${DEMO_CLUSTER_NAME:-kind}")
  export KUBECONFIG
fi

# Cleanup previous example runs
kubectl --namespace='gloo-system' delete virtualservice/default && true # ignore errors

# Install example application
kubectl --namespace='default' apply \
  --filename="$GLOO_DEMO_RESOURCES_HOME/petstore.yaml"

# glooctl create virtualservice \
#   --name='default' \
#   --namespace='gloo-system'

# glooctl add route \
#   --name default \
#   --path-prefix='/' \
#   --dest-name='default-petstore-8080' \
#   --dest-namespace='gloo-system'

kubectl apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  displayName: default
  virtualHost:
    domains:
    - '*'
    routes:
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-petstore-8080
            namespace: gloo-system
    virtualHostPlugins:
      extensions:
        configs:
          waf:
            settings:
              coreRuleSet:
                customSettingsString: |
                  # default rules section
                  SecRuleEngine On
                  SecRequestBodyAccess On
                  # CRS section
                  SecDefaultAction "phase:1,log,auditlog,deny,status:403"
                  SecDefaultAction "phase:2,log,auditlog,deny,status:403"
                  SecAction "id:900000,phase:1,nolog,pass,t:none,setvar:tx.paranoia_level=4"
                  SecAction "id:900230,phase:1,nolog,pass,t:none,setvar:'tx.allowed_http_versions=HTTP/1.0 HTTP/1.1 HTTP/2 HTTP/2.0'"
                  SecAction "id:900250,phase:1,nolog,pass,t:none,setvar:'tx.restricted_headers=/proxy/ /lock-token/ /content-range/ /translate/ /if/ /bar/'"
                  SecAction "id:900990,phase:1,nolog,pass,t:none,setvar:tx.crs_setup_version=310"
              ruleSets:
              - ruleStr: |
                  # Turn rule engine on
                  SecRuleEngine On
                  SecRule REQUEST_HEADERS:User-Agent "scott" "id:107,phase:1,log,deny,t:lowercase,status:403,msg:'blocked scammer'"
EOF

sleep 10

# kubectl --namespace='gloo-system' get virtualservice/default --output yaml

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch='true'

# Port forward the Gloo proxy to a localhost port

PROXY_PID_FILE="$SCRIPT_DIR/proxy_pf.pid"
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch='true'
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

# PROXY_URL=$(glooctl proxy url)
PROXY_URL='http://localhost:8080'

sleep 10

printf "\nShould return 200\n"
# curl --silent --write-out "\n%{http_code}\n" "$PROXY_URL/api/pets/1" | jq
http --json "$PROXY_URL/api/pets/1"

# Rule 920420 - works as expected; looks like it triggers 2 rules - no host header and unsupported content type
printf "\nShould return 403\n"
# curl --silent --verbose --header "Content-Type: application/foo" --data "blah" "$PROXY_URL/api/pets/1"
http --verbose "$PROXY_URL/api/pets/1" Content-Type:application/foo <<<'blah'

# Rule 913100 - broken
printf "\nShould return 403\n"
# curl --silent --verbose --header "User-Agent: Nikto" "$PROXY_URL/api/pets/1"
http --verbose "$PROXY_URL/api/pets/1" 'User-Agent:Nikto'

# Rule 107 - works as expected based on custom SecRule
printf "\nShould return 403\n"
# curl --silent --verbose --header "User-Agent: Scott" "$PROXY_URL/api/pets/1"
http --verbose "$PROXY_URL/api/pets/1" 'User-Agent:Scott'

# Rule 932160 - broken
printf "\nShould return 403\n"
# curl --silent --verbose "$PROXY_URL/api/pets/1?exec=/bin/bash"
http --verbose "$PROXY_URL/api/pets/1?exec=/bin/bash"

# Rule 900250 - broken
printf "\nShould return 403\n"
# curl --silent --verbose --header "proxy: true" "$PROXY_URL/api/pets/1"
http --verbose "$PROXY_URL/api/pets/1" proxy:true

# Rule 900250 (customized in virtual service config) - broken
printf "\nShould return 403\n"
# curl --silent --verbose --header "bar: baz" "$PROXY_URL/api/pets/1"
http --verbose "$PROXY_URL/api/pets/1" bar:baz

# Rule 942500 - broken
printf "\nShould return 403\n"
# curl --silent --verbose "$PROXY_URL/api/pets/1?id=9999+or+{if+length((/*!5000select+username/*!50000from*/user+where+id=1))>0}"
http --verbose "$PROXY_URL/api/pets/1?id=9999+or+{if+length((/*!5000select+username/*!50000from*/user+where+id=1))>0}"

# Rule 930110, 930120, 932160 - broken
printf "\nShould return 403\n"
# curl --silent --verbose "$PROXY_URL/api/pets/1?foo=../etc/passwd"
http --verbose "$PROXY_URL/api/pets/1?foo=../etc/passwd"
