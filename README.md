# Bitpoke Boost Guide

## Overview

Bitpoke Boost. [Learn more](https://www.bitpoke.io/)

> [!NOTE]
> The recommended way to install Boost is through the [Google Cloud Marketplace](https://console.cloud.google.com/marketplace/details/bitpoke-public/boost).
> If you want to install Boost manually, you can do so by following the next steps.

## Installation prerequisites

You can use [Cloud Shell](https://cloud.google.com/shell/) or a local workstation to follow the steps below.

[![Open in Cloud Shell](http://gstatic.com/cloudssh/images/open-btn.svg)](https://console.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/bitpoke/boost-public&cloudshell_open_in_editor=README.md&cloudshell_tutorial=README.md)


### Set up command-line tools

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

### Create or reuse a Google Kubernetes Engine (GKE) cluster

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

### Clone this repo

Clone this repo and the associated tools repo:

```sh
git clone https://github.com/bitpoke/boost-public.git
```

### Install the Application resource definition

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

## Configure OpenID Connect

Boost uses OpenID Connect for authentication. You can use any OIDC provider (like Auth0 or Google Cloud).

To configure Google Cloud, you can follow the tutorial at: https://www.bitpoke.io/docs/app-for-wordpress/installation/authentication/

## Install the app

If you are using the visual install interface from the Google Cloud Marketplace, you can skip now to [Expose the application to the internet](#expose-the-application-to-the-internet)

### Configure the app with environment variables

Set up the image tag:

It is advised to use stable image reference which you can find on [Marketplace Container Registry](https://us-docker.pkg.dev/bitpoke-public/boost/boost).
Example:

```sh
export TAG="0.1.9"
```

Alternatively you can use short tag which points to the latest image for selected version.

> [!WARNING]
> This tag is not stable and referenced image might change over time.

```sh
export TAG="0.1"
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

### Install Custom Resource Definitions (CRDs)

```sh
helm template charts/boost --set 'crd.enable=true' -s 'templates/crd/*' | kubectl apply -f-
```


### Create the application Service Account

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

### Expand the manifest template

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

### Apply the manifest to your Kubernetes cluster

To apply the manifest to your Kubernetes cluster, use `kubectl`:

```sh
kubectl apply -f "${APP_INSTANCE_NAME}_manifest.yaml" --namespace "${NAMESPACE}"
```

### View the app in the Cloud Console

To get the Cloud Console URL for your app, run the following command:

```sh
echo "https://console.cloud.google.com/kubernetes/application/${REGION}/${CLUSTER}/${NAMESPACE}/${APP_INSTANCE_NAME}?project=${PROJECT_ID}"
```

To view the app, open the URL in your browser.

## Create the Cloud SQL instance 

Go to https://console.cloud.google.com/sql/instances and create an instance.

## Expose the application to the internet

To expose the application to the internet, you can use the [Gateway](https://gateway-api.sigs.k8s.io/) resource. Or alternatively, you could use an Ingress resource, but this is not documented here.
Now, you can run the ./install.sh script:

```sh
./install.sh
```

Wait until the HTTPRoute is Accepted and ready to route traffic.

```sh
kubectl describe httproute -n ${NAMESPACE} ${APP_INSTANCE_NAME}
```

## Post-installation steps


### Seed the application with global resources

```sh
./seed.sh > seed_manifest.yaml
kubectl apply -f seed_manifest.yaml
```
### Enjoy!

The application is now available under the selected domain!
