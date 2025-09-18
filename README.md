# Bitpoke Boost Guide

## Overview

Bitpoke Boost. [Learn more](https://www.bitpoke.io/)

> [!NOTE]
> The recommanded way to install Boost is through the [Google Cloud Marketplace](https://console.cloud.google.com/marketplace/details/bitpoke-public/boost).
> If you want to install Boost manually, you can do so by following the next steps.

## Installation

You can use [Cloud Shell](https://cloud.google.com/shell/) or a local workstation to follow the steps below.

[![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/bitpoke/boost-public&cloudshell_open_in_editor=README.md&cloudshell_tutorial=README.md)

### Prerequisites

#### Set up command-line tools

You'll need the following tools in your development environment. If you are using
Cloud Shell, then `gcloud`, `kubectl`, Docker, and Git are installed in your
environment by default.

* [gcloud](https://cloud.google.com/sdk/gcloud/)
* [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)
* [docker](https://docs.docker.com/install/)
* [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
* [helm](https://helm.sh/)

```sh
echo "gcloud: $(gcloud --version | head -n1)"
echo "kubectl: $(kubectl version --client | head -n1)"
echo "docker: $(docker --version)"
echo "git: $(git version)"
echo "helm: $(helm version --short)"
```

Configure `gcloud` as a Docker credential helper:

```sh
gcloud auth configure-docker
```

#### Create or reuse a Google Kubernetes Engine (GKE) cluster

Set cluster parameters:

```sh
export PROJECT_ID=
export REGION=us-central1
export CLUSTER=boost-cluster
```

Create a new GKE Autopilot cluser or, if you already have a cluster, you can skip
this step and use your existing cluster. You can also create a reguar cluster,
by using the `gcloud container clusters create` command instead of
`gcloud container clusters create-auto`:

```sh
gcloud container clusters create-auto "$CLUSTER" --project "$PROJECT_ID" --region "$REGION"
```

Configure `kubectl` to connect to the new cluster:

```sh
gcloud container clusters get-credentials "$CLUSTER" --project "$PROJECT_ID" --region "$REGION"
```

#### Clone this repo

Clone this repo and the associated tools repo:

```sh
git clone https://github.com/bitpoke/boost-public.git
```

#### Install the Application resource definition

An Application resource is a collection of individual Kubernetes components, such
as Services, StatefulSets, and so on, that you can manage as a group.

To set up your cluster to understand Application resources, run the following
command:

```sh
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"
```

You need to run this command once.

The Application resource is defined by the
[Kubernetes SIG-apps](https://github.com/kubernetes/community/tree/master/sig-apps)
community. The source code can be found on
[github.com/kubernetes-sigs/application](https://github.com/kubernetes-sigs/application).

#### Configure OpenID Connect

Boost uses OpenID Connect for authentication. You can use any OIDC provider (like Auth0 or Google Cloud).

To configure Google Cloud, you can follow the tutorial at: https://www.bitpoke.io/docs/app-for-wordpress/installation/authentication/

### Install the app

#### Configure the app with environment variables

Set up the image tag:

It is advised to use stable image reference which you can find on [Marketplace Container Registry](https://us-docker.pkg.dev/bitpoke-public/boost/boost).
Example:

```sh
export TAG="1.0.0"
```

Alternatively you can use short tag which points to the latest image for selected version.

> [!WARNING]
> This tag is not stable and referenced image might change over time.

```sh
export TAG="1.0"
```

Configure the image registry:

```sh
export REGISTRY="us-docker.pkg.dev/bitpoke-public/boost"
```

Choose the instance name and namespace for the app. In most cases, you can use the `default` namespace.

```sh
export APP_INSTANCE_NAME=bitpoke-boost-1
export NAMESPACE=default
```

Configure the application parametes.

```sh
export BOOST_BRANDING_NAME=
export BOOST_BRANDING_LOGO_URL=

export OIDC_ISSUER_URL=https://accounts.google.com
export OIDC_CLIENT_ID=
export OIDC_CLIENT_SECRET=
export OIDC_REDIRECT_URL= # https://example.com/auth/callback
```

#### Install Custom Resource Definitions (CRDs)

```sh
helm template charts/boost --set 'crd.enable=true' -s 'templates/crd/*' | kubectl apply -f-
```


#### Create the application Service Account

Create the Application default roles:
```sh
helm template -n "$NAMESPACE" "$APP_INSTANCE_NAME" charts/boost \
    --set "controllerManager.serviceAccountName=$APP_INSTANCE_NAME" \
    --set "rbac.enable=true" \
    -s templates/rbac/wordpress_job_invoker_role.yaml \
    -s templates/rbac/leader_election_role.yaml \
    -s templates/rbac/role.yaml | \
kubectl apply -f-
```

Create the service account for the application:
```sh
helm template -n "$NAMESPACE" "$APP_INSTANCE_NAME" charts/boost \
    --set "controllerManager.serviceAccountName=$APP_INSTANCE_NAME" \
    --set "rbac.enable=true" \
    -s templates/rbac/service_account.yaml | \
kubectl apply -f-
````

Create the cluster role binding for the service account:
```sh
helm template -n "$NAMESPACE" "$APP_INSTANCE_NAME" charts/boost \
    --set "controllerManager.serviceAccountName=$APP_INSTANCE_NAME" \
    --set "rbac.enable=true" \
    -s templates/rbac/leader_election_role_binding.yaml \
    -s templates/rbac/role_binding.yaml | \
kubectl apply -f-
```

#### Expand the manifest template

Use `helm template` to expand the template. We recommend that you save the
expanded manifest file for future updates to your app.

```sh
helm template -n "$NAMESPACE" "$APP_INSTANCE_NAME" charts/boost \
    --set "controllerManager.serviceAccountName=$APP_INSTANCE_NAME" \
    --set "env.BOOST_BRANDING_NAME=$BOOST_BRANDING_NAME" \
    --set "env.BOOST_BRANDING_LOGO_URL=$BOOST_BRANDING_LOGO_URL" \
    --set "env.OIDC_ISSUER_URL=$OIDC_ISSUER_URL" \
    --set "env.OIDC_CLIENT_ID=$OIDC_CLIENT_ID" \
    --set "env.OIDC_CLIENT_SECRET=$OIDC_CLIENT_SECRET" \
    --set "env.OIDC_REDIRECT_URL=$OIDC_REDIRECT_URL" \
    --set "controllerManager.container.image.repository=$REGISTRY/boost" \
    --set "controllerManager.container.image.tag=$TAG" \
    --set "values.mutagen.image.repository=$REGISTRY/boost/syncer" \
    --set "values.mutagen.image.tag=$TAG" \
    --set "wpInvokerImage=$REGISTRY/boost/wp-invoker:$TAG" \
    --no-hooks \
    --skip-crds --set 'crd.enable=false'\
    > "${APP_INSTANCE_NAME}_manifest.yaml"
```

#### Apply the manifest to your Kubernetes cluster

To apply the manifest to your Kubernetes cluster, use `kubectl`:

```sh
kubectl apply -f "${APP_INSTANCE_NAME}_manifest.yaml" --namespace "${NAMESPACE}"
```

#### View the app in the Cloud Console

To get the Cloud Console URL for your app, run the following command:

```sh
echo "https://console.cloud.google.com/kubernetes/application/${REGION}/${CLUSTER}/${NAMESPACE}/${APP_INSTANCE_NAME}?project=${PROJECT_ID}"
```

To view the app, open the URL in your browser.

### Expose the application to the internet

To expose the application to the internet, you can either use an Ingress or the new [Gateway](https://gateway-api.sigs.k8s.io/) resource.

#### Create the gateway resource

First, createh the Google Cloud Certificate Map resource to manage TLS certificates:
```sh
gcloud certificate-manager maps create --location=global ${APP_INSTANCE_NAME}-certmap
```

Then, create the Kubernetes Gateway resource:
```terminal
kubectl apply -f- <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  annotations:
    networking.gke.io/certmap: ${APP_INSTANCE_NAME}-certmap
  name: ${APP_INSTANCE_NAME}
  namespace: ${NAMESPACE}
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
```

Wait for the gateway to be programmed:

```sh
kubectl -n ${NAMESPACE} wait --for=condition=Programmed gateway/${APP_INSTANCE_NAME} --timeout=600s
```

Note the gateway IP address:

```sh
kubectl -n ${NAMESPACE} get gateway/${APP_INSTANCE_NAME} -o jsonpath='{range .status.addresses[*]}{.value}{"\n"}{end}'
```

#### Update DNS records

Update the DNS records to point to the Gateway IP.

Export the application domain name:

```sh
export APP_DOMAIN= # example.com (without http/https prefix)
```

#### Create a Certificate and add it to the Certificate Map

```sh
gcloud certificate-manager certificates create "$APP_INSTANCE_NAME" --domains="$APP_DOMAIN"
gcloud certificate-manager maps entries create "$APP_INSTANCE_NAME" \
    --location=global --map="${APP_INSTANCE_NAME}-certmap" \
    --hostname="$APP_DOMAIN" --certificates="$APP_INSTANCE_NAME"
```

Wait for the certificate to be ready (this may take a few minutes, up to half an hour):

```sh
watch gcloud certificate-manager certificates describe "$APP_INSTANCE_NAME"
```

#### Route the application through the gateway

```terminal
kubectl apply -f- <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  labels:
    app.kubernetes.io/name: boost
    app.kubernetes.io/instance: ${APP_INSTANCE_NAME}
    control-plane: controller-manager
  name: ${APP_INSTANCE_NAME}
  namespace: ${NAMESPACE}
spec:
  hostnames:
  - ${APP_DOMAIN}
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: ${APP_INSTANCE_NAME}
    namespace: ${NAMESPACE}
  rules:
  - backendRefs:
    - group: ""
      kind: Service
      name: ${APP_INSTANCE_NAME}
      port: 80
      weight: 1
    matches:
    - path:
        type: PathPrefix
        value: /
EOF
```

Wait until the HTTPRoute is Accepted and ready to route traffic.

```sh
kubectl describe httproute -n ${NAMESPACE} ${APP_INSTANCE_NAME}
```

### Enjoy!

The application is now available under the selected domain!

## Post-installation steps

### Create the global namespace

Boost uses a dedicated namespace for global resources. You can create it with the following command:

```sh
kubectl create namespace boost-global
```

#### Cereate a Certificate Map for Gateway resource

```sh
gcloud certificate-manager maps create --location=global boost-cert-map
```

### Add Google Cloud IAM permissions

#### Add permissions to manage certificates

In order to manage certificates, Bitpoke Boost needs the `roles/certificatemanager.owner` role to the service
account used by the application.

To grant it using Workload Identity, you can use the following command:
```sh
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --role roles/certificatemanager.owner \
    --member "principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${NAMESPACE}/sa/${APP_INSTANCE_NAME}"
```

#### Add permissions to manage Cloud SQL instances
```sh
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --role roles/cloudsql.client \
    --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER}"
```

#### Add permissions to access Cloud Storage Bucket
```sh
gcloud storage buckets add-iam-policy-binding gs://${BUCKET} \
    --role roles/storage.objectUser \
    --member "principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/kubernetes.cluster/https://container.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER}"
````

### Seed the application with global resources

```sh
./seed.sh > seed_manifest.yaml
kubectl apply -f seed_manifest.yaml
```

