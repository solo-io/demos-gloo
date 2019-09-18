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

# source "$SCRIPT_DIR/../working_environment.sh"

# Install example application
# kubectl --namespace='default' apply \
#   --filename="$SCRIPT_DIR/../resources/petstore.yaml"
kubectl --namespace='default' apply \
  --filename='https://raw.githubusercontent.com/sololabs/demos2/master/resources/petstore.yaml'

# Cleanup old examples
kubectl --namespace='gloo-system' delete virtualservice/default && true # ignore errors

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
              coreRuleSet: {}
                # customSettingsString: |
                #   # default rules section
                #   SecRuleEngine On
                #   SecRequestBodyAccess On
                #   # CRS section
                #   SecDefaultAction "phase:1,log,auditlog,pass"
                #   SecDefaultAction "phase:2,log,auditlog,pass"
                #   SecAction "id:900990,phase:1,nolog,pass,t:none,setvar:tx.crs_setup_version=320"
EOF

sleep 10

# kubectl --namespace='gloo-system' get virtualservice/default --output yaml

# Wait for demo application to be fully deployed and running
kubectl --namespace='default' rollout status deployment/petstore --watch=true

PROXY_PID_FILE=$SCRIPT_DIR/proxy_pf.pid
if [[ -f $PROXY_PID_FILE ]]; then
  xargs kill <"$PROXY_PID_FILE" && true # ignore errors
  rm "$PROXY_PID_FILE"
fi
kubectl --namespace='gloo-system' rollout status deployment/gateway-proxy-v2 --watch=true
( (kubectl --namespace='gloo-system' port-forward service/gateway-proxy-v2 8080:80 >/dev/null) & echo $! > "$PROXY_PID_FILE" & )

printf "Should return 200\n"
# curl --silent --write-out "%{http_code}\n" http://localhost:8080/api/pets/1 | jq
http --json http://localhost:8080/api/pets/1

printf "Should return 403\n"
# curl --silent --write-out "%{http_code}\n" --header "User-Agent: Nikto" http://localhost:8080/api/pets/1 | jq
http --json http://localhost:8080/api/pets/1 User-Agent:Nikto
