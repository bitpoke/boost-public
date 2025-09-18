#!/bin/bash

if [ -n "$1" ] && [ -f "$1" ]; then
  source "$1"
fi

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

setvar PROJECT_ID ""
setvar REGION ""
setvar CLUSTER ""
setvar CLUSTER_LOCATION "$REGION"
setvar NAMESPACE "boost"
setvar APP_INSTANCE_NAME "boost-1"
setvar CERTIFICATE_MAP_NAME "boost-cert-map"
setvar DATABASE_INSTANCE ""
setvar DATABASE_USER ""
setvar DATABASE_PASSWORD "" false
setvar BUCKET ""

export DATABASE_PASSWORD_ENCODED=$(echo -n $DATABASE_PASSWORD | base64)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

cat <<EOF >&2
# -----------------------------------------------------------------------------
#
# Give the following permissions to the GKE cluster with Workload Identity enabled
# NOTE: Workload Identity is applied ONLY to node pools created after enabling it on the cluster.
#
# Allow access to Certificate Manager for all pods in Boost application namespace
#
gcloud projects add-iam-policy-binding ${PROJECT_ID} \\
    --role roles/certificatemanager.owner \\
    --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/namespace/${NAMESPACE}"

# Allow access to Cloud SQL for all pods in the cluster
gcloud projects add-iam-policy-binding ${PROJECT_ID} \\
    --role roles/cloudsql.client \\
    --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER}"

# Allow access to GCS bucket for media storage to all pods in the cluster
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \\
    --role roles/storage.objectUser \\
    --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER}"

# Restart the pods in the Boost application namespace to pick up new permissions
kubectl -n boost scale deployment/${APP_INSTANCE_NAME} --replicas=0
sleep 10
kubectl -n boost scale deployment/${APP_INSTANCE_NAME} --replicas=1
EOF

cat <<EOF
#
# Save the following manifest to a file and apply it with:
# kubectl apply -f <file> --context gke_${PROJECT_ID}_${CLUSTER_LOCATION}_${CLUSTER}
#
# -- seed.yaml ------------------------------------------------------------------------------------
#
---
apiVersion: v1
kind: Namespace
metadata:
  name: boost-global
---
apiVersion: boost.bitpoke.io/v1
kind: ReleaseChannel
metadata:
  name: stable
  namespace: boost-global
  annotations:
    boost.bitpoke.io/display-name: "Stack Runtime"
spec:
  image:
    repository: bitpoke/wordpress-runtime
    tag: "6.8.3"
  values:
    cli:
      image:
        repository: bitpoke/wordpress-runtime
        tag: "6.8.3"
    wordpress:
      documentRoot: "/app/web"
      useExistingDocumentRoot: true
---
apiVersion: v1
kind: Secret
metadata:
  name: playground-db-creds
  namespace: boost-global
type: Opaque
data:
  mysql-root-password: ${DATABASE_PASSWORD_ENCODED}
---
apiVersion: boost.bitpoke.io/v1
kind: MySQLDatabase
metadata:
  name: default
  namespace: boost-global
  annotations:
    boost.bitpoke.io/display-name: "playground-db (euroep-west4)"
spec:
  address:
    value: ${PROJECT_ID}:${REGION}:${DATABASE_INSTANCE}?private=true
  rootPassword:
    valueFrom:
      secretKeyRef:
        key: mysql-root-password
        name: playground-db-creds
---
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
          from: Selector
          selector:
            matchLabels:
              boost.bitpoke.io/project: "true"
      name: http
      port: 80
      protocol: HTTP
    - allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              boost.bitpoke.io/project: "true"
      name: https
      port: 443
      protocol: HTTPS
---
apiVersion: boost.bitpoke.io/v1
kind: PodResources
metadata:
  name: default
  namespace: boost-global
  annotations:
    boost.bitpoke.io/display-name: "default"
spec:
  resources:
    requests:
      cpu: 1
      memory: 2Gi
---
apiVersion: boost.bitpoke.io/v1
kind: PodResources
metadata:
  name: small-250m-1gi
  namespace: boost-global
  annotations:
    boost.bitpoke.io/display-name: "small"
spec:
  resources:
    requests:
      cpu: 250m
      memory: 1Gi
---
apiVersion: boost.bitpoke.io/v1
kind: PodPlacement
metadata:
  name: default
  namespace: boost-global
spec:
  storageClassName: standard-rwo
---
apiVersion: boost.bitpoke.io/v1
kind: PodPlacement
metadata:
  name: spot
  namespace: boost-global
spec:
  storageClassName: standard-rwo
  nodeSelector:
    cloud.google.com/gke-spot: "true"
  tolerations:
    - effect: NoSchedule
      key: cloud.google.com/gke-spot
      operator: Equal
      value: "true"
---
apiVersion: boost.bitpoke.io/v1
kind: MediaStorage
metadata:
  name: default
  namespace: boost-global
  annotations:
    boost.bitpoke.io/display-name: "gs://${BUCKET}"
spec:
  subdirectory: projectAndSite
  gcs:
    bucket: ${BUCKET}
EOF
