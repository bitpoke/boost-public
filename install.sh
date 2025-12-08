#!/bin/bash

setvar() {
    local var_name="$1"
    local default="$2"
    local required="${3:-true}"
    if [ -z "${!var_name}" ]; then
        read -p "$var_name [default: $default]: " input_value
        export $var_name="${input_value:-$default}"
    fi
    if [ -z "${!var_name}" ] && [  "$required" == "true" ]; then
        echo >&2 "$var_name is required"
        exit 1
    fi
}

setvar NAMESPACE "boost"
setvar APP_INSTANCE_NAME "boost-1"
setvar CERTIFICATE_MAP_NAME "boost-cert-map"
setvar APP_DOMAIN ""

gcloud certificate-manager maps create --location=global "${CERTIFICATE_MAP_NAME}"

kubectl apply -f- <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  annotations:
    networking.gke.io/certmap: ${CERTIFICATE_MAP_NAME}
  name: default
  namespace: boost-global
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - allowedRoutes:
        namespaces:
          from: All
      name: http
      port: 80
      protocol: HTTP
    - allowedRoutes:
        namespaces:
          from: All
      name: https
      port: 443
      protocol: HTTPS
EOF


echo >&2 'Wait for the gateway to be programmed (this may take several minutes)...'
kubectl -n boost-global wait --for=condition=Programmed gateway/default --timeout=600s

echo >&2 'Gateway IP address:'
kubectl -n boost-global get gateway/default -o jsonpath='{range .status.addresses[*]}{.value}{"\n"}{end}'

read -rp "Update your DNS to point to the gateway IP address, then press [Enter] to continue..."

gcloud certificate-manager certificates create "${APP_INSTANCE_NAME}" --domains="${APP_DOMAIN}"
gcloud certificate-manager maps entries create "${APP_INSTANCE_NAME}" \
    --location=global --map="${CERTIFICATE_MAP_NAME}" \
    --hostname="${APP_DOMAIN}" --certificates="${APP_INSTANCE_NAME}"


read -rp "Press [Enter] once the certificate is active..."

kubectl apply -f- <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  labels:
    app.kubernetes.io/name: boost
    app.kubernetes.io/instance: boost-1
    control-plane: controller-manager
  name: boost-1
  namespace: ${NAMESPACE}
spec:
  hostnames:
  - ${APP_DOMAIN}
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: ${APP_INSTANCE_NAME}
    namespace: boost-global
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: boost-1
      port: 80
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
EOF
