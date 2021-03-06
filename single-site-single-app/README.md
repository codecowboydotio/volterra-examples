# Volterra Example - Single App, Single Site

This is a teraform example of a single application and a single site.

This is based on the documentation available at [Volterra.io](http://volterra.io)

## Explanation

As part of learning the Volterra platform, I have created a few scenario's that shows different functionality. 
This scenario is the single application, within a single namesapce and single site.

This will become clearer over the course of the README.


## Architecture

The architecture is relatively simple. I have a single application that is an API that has multiple enpoints.
This application is distributed to a number of volterra edge sites. In the Volterra lexicon these are called Regional Edge sites or RE.

Volterra edge sites are sites that are fully managed by Volterra. This makes them a good place to start, and to get up and running quickly.

### Applications

I have a single application that is an API - the starwars API.
It has the following endpoints

/people
/starships
/vehicles
/species
/films

Each endpoint has a number of records (and some refer to each other).

At the / endpoint there is a simple website.


### Load Generator

I have created a load generator application. This application does the following things:

1. Uses the tor network in order to present different source IP addresses
2. Runs a basic shell script to push some traffic through the API endpoints.

### Namespace

There is a single namespace in the example application. This is created by the terraform scripts.

This is configured by the terraform variable **ns**. 

```
variable "ns" { default = "s-vk" }
```

In my example, I'm using my initials as the namespace 

### Sites

Volterra has the concept of sites. Within the example, there is a single site. 
The site is configured using a concatenation of the terraform variable namespace name, and adding the suffix **vs** to denote a virtual site.

```
name      = format("%s-vs", volterra_namespace.ns.name)
```

The net effect is that the namespace name has **vs** added to it, so in this example, it will be **s-vk-vs**.

The resource that I use in terraform to create the virtual site is below:

```
resource "volterra_virtual_site" "main" {
  name      = format("%s-vs", volterra_namespace.ns.name)
  namespace = volterra_namespace.ns.name
  depends_on = [time_sleep.ns_wait]

  labels = {
    "ves.io/siteName" = "ves-io-sg3-sin"
  }
  site_selector {
    expressions = var.site_selector
  }
  site_type = "REGIONAL_EDGE"
}
```

The three important pieces here are:

- labels
- site selector
- site type

Much like Kubernetes Volterra uses labels and selectors to identify objects. 
Some of the terminology overlaps with Kubernetes terminology, but don't be worried, I've tried to show which pieces are specific to the volterra control plane, and which are not.

![Volterra Site Concepts](volterra-namespace-site.JPG)

**Labels**

This is a label that I can use to identify this particular object. This object is identified using the site name.

**Site Selector**

This is a selector that I can use to choose how I interact with other labels in the volterra world. I'm using the variable **site_selector** which maps to three volterra sites.

```
variable "site_selector" { default = [ "ves.io/siteName in (ves-io-sg3-sin, ves-io-ny8-nyc, ves-io-os1-osa)" ] }
```

This has the effect of choosing the three volterra sites when I deploy anything using this partcular site.


**Site Type**

The site type is the type of site I'm going to install.
The allowed values here are **CUSTOMER_EDGE** or **REGIONAL_EDGE**.
Regional edge means "in a volterra point of presence", and Customer Edge means "in your own point of presence".

I have selected regional edge as it's less work, and means that I can be up and running quickly.

### Virtual Kubernetes

There is also a virtual kubernetes site, vk8s for short. This is associated with the site, this is explained later and is primarily for deployment purposes.

Virtual kubernetes is a kubernetes like API that allows me to run a virtual kubernetes deployment within the Volterra RE (Regional Edge) site. The virtual kubernetes site and API allows me to deploy pods and create services. This allows me to use standard kubernetes devices, such as manifests, and so on to deploy my applications.

```
resource "volterra_virtual_k8s" "vk8s" {
  name      = format("%s-vk8s", volterra_namespace.ns.name)
  namespace = volterra_namespace.ns.name
  depends_on = [volterra_virtual_site.main]

  vsite_refs {
    name      = volterra_virtual_site.main.name
    namespace = volterra_namespace.ns.name
  }
}
```

The **vsite_refs** is the important part here. 
This associates this virtual kubernetes site with a volterra site. This is a reference to another object within the Volterra system. In this case, we are associating the virtual site we created above with our virtual kubernetes instance.



### API Discovery

I have enabled API discovery - as the application I have deployed is an API.

The mechanism to do this is to enable what we call an "application type". 
The application type can be used to contain what we call "features". 
Creating a custom one just makes it easier to handle later on.
I have named it after my application (it makes sense).

Each application type has a number of features. 
I have enabled all of the features, but you can read more about them [here](https://www.volterra.io/docs/how-to/app-security/apiep-discovery-control?query=app%20type)

```
resource "volterra_app_type" "at" {
  // This naming simplifies the 'mesh' cards
  name      = var.manifest_app_name
  namespace = "shared"
  features {
    type = "BUSINESS_LOGIC_MARKUP"
  }
  features {
    type = "USER_BEHAVIOR_ANALYSIS"
  }
  features {
    type = "PER_REQ_ANOMALY_DETECTION"
  }
  features {
    type = "TIMESERIES_ANOMALY_DETECTION"
  }
  business_logic_markup_setting {
    enable = true
  }
}
```

This essentially sets up a custom application type with all of the features enabled. 
This will automatically create a card named after your app type when you deploy your application.


### Origin Pool

The origin pool represents the kubernetes service that you created earlier. 
Rather than performing a "normal" ingress, you create an origin pool, which can represent a normal origin pool like a network IP address, or a domain name. An origin pool can also represent or point to a volterra voltstack service within a namespace.

In our case this will point to a volterra service running in our site. 
The format for this is to use the servicename and namespace in the form of "servicename.namespace"

```
resource "volterra_origin_pool" "backend" {
  name                   = format("%s-be", var.manifest_app_name)
  namespace              = volterra_namespace.ns.name
  depends_on             = [time_sleep.ns_wait]
  description            = format("Origin pool pointing to backend k8s service running in main-vsite")
  loadbalancer_algorithm = "ROUND ROBIN"
  origin_servers {
    k8s_service {
      inside_network  = false
      outside_network = false
      vk8s_networks   = true
      service_name    = format("${var.servicename}.%s", volterra_namespace.ns.name)
      site_locator {
        virtual_site {
          name      = volterra_virtual_site.main.name
          namespace = volterra_namespace.ns.name
        }
      }
    }
  }
  port               = 3000
  no_tls             = true
  endpoint_selection = "LOCAL_PREFERRED"
}
```

This effectively exposes the kubernetes service onto the wider volterra network.

The reason that it's done this way is that using an origin pool, we can expose other types of services onto the volterra network, a kubernetes service within a namespace is simply one type. This represents a more generic way of exposing objects.

### Load Balancer

The last piece of the puzzle is to expose a service externally to the world
Again, this is via a load balancer rather than any specific ingress annotation.

The reason for this is that a kubernetes service is just one type of object that can be exposed. 
In terms of exposing our web app to the outside world, we do it via the origin pool.

In many ways, the load balancer object has many of the characteristics of a "normal" load balancer object.
It has layer 7 rewrite and routing functionality, as well as the ability to select an origin pool.

The origin pool being selected can be any type that has been created. 

In our case, we select the origin pool we created above.

```
resource "volterra_http_loadbalancer" "backend" {
  name                            = format("%s-be", var.manifest_app_name)
  namespace                       = volterra_namespace.ns.name
  depends_on                      = [time_sleep.ns_wait]
  description                     = format("HTTP loadbalancer object for %s origin server", var.manifest_app_name)
  domains                         = ["${var.manifest_app_name}.${var.domain}"]
  advertise_on_public_default_vip = true
  labels                          = { "ves.io/app_type" = volterra_app_type.at.name }
  default_route_pools {
    pool {
      name      = volterra_origin_pool.backend.name
      namespace = volterra_namespace.ns.name
    }
  }
  https_auto_cert {
    add_hsts      = false
    http_redirect = true
    no_mtls       = true
  }
  more_option {
    response_headers_to_add {
        name   = "Access-Control-Allow-Origin"
        value  = "*"
        append = false
    }
  }
  disable_waf                     = true
  disable_rate_limit              = true
  round_robin                     = true
  service_policies_from_namespace = true
  no_challenge                    = true
}
```

The important things in this resource are that we have used our app type that we created earlier as a label on the load balancer.

We have also pointed this loa balancer to our origin pool that we created earlier.

In addition to this, we have added some "more options". This allows us to add a response header of **Access-Control-Allow_Origin** with a wildcard. This essentially allows anywhere as an origin should we want to use a certificate that is out of date. It's a way of working around some CORS problems. Not elegant.... but this is a demonstration after all. :)

## Variables
The following variables are used in the terraform.

| Variable | Description |
|------|------|
| `ns` | This is the namespace that will be created and your objects will be deployed in |
| `domain` | This is the domain that has been delegated to volterra. Ex: my.domain.com |
| `servicename` | This is the svc name that will be created as part of your deployment. This will be reflected in the manifest within the mainfests directory |
| `manifest_app_name` | This is the name of the application in the deployment. It will be used to name all associated object in volterra and kubernetes. It is also used in the kubernetes manifest as a label and selector. |
| `loadgen_manifest_app_name` | This is the name of the load generator application in the deployment. It will be used to name all associated objects in volterra and kubernetes as they relate to the load generator app. |
| `site_selector` | This is the selector used as part of the virtual site to select the "real" sites. |


## Kubernetes credentials

As part of creating a virtual kubernetes cluster, we also create some kubernetes credentials objects. This is essentially a kubeconfig file that we will download and then use that created credential to create a kubeconfig file.

The kubeconfig file is used to interact with our cluster.

```
resource "volterra_api_credential" "cred" {
  name      = format("%s-api-cred", var.manifest_app_name)
  api_credential_type = "KUBE_CONFIG"
  virtual_k8s_namespace = volterra_namespace.ns.name
  virtual_k8s_name = volterra_virtual_k8s.vk8s.name
}


resource "local_file" "kubeconfig" {
    content = base64decode(volterra_api_credential.cred.data)
    filename = format("%s/%s", path.module, format("%s-vk8s.yaml", terraform.workspace))

    depends_on = [time_sleep.vk8s_cred_wait]
}
```
## Kubernetes deployment

The kubernetes deployment is relatively simple. It uses the kubeconfig file that we generated above to deploy applications from the **manifests** directory. As part of creating the manifests, we pass variables into the manifest files - the mainfest files are really just terraform templates where we can fill out the manifest at runtime using variables from our vars file (see below).

```
provider "kubectl" {
  config_path = "./default-vk8s.yaml"
}

data "kubectl_path_documents" "manifests" {
  pattern = "./manifests/*.yml"
  vars = {
      namespace  = var.ns
      manifest_app_name = var.manifest_app_name
      loadgen_manifest_app_name = var.loadgen_manifest_app_name
      servicename = var.servicename
      domain = var.domain
  }
}

resource "kubectl_manifest" "documents" {
    count     = length(data.kubectl_path_documents.manifests.documents)
    yaml_body = element(data.kubectl_path_documents.manifests.documents, count.index)
#    //This provider doesn't enforce NS from kubeconfig context
    override_namespace = var.ns
    depends_on = [local_file.kubeconfig, data.kubectl_path_documents.manifests]
}
```

## Kubernetes manifests

The directory "manifests" contains two mainfests. 

- swapi-backend.yml: This is the backend application that is an API.
- swapi-loadgen.yml: This is a load generator that I run to generate "fake" traffic to my API.

Each manifest is a terraform template.

One is a deployment and an associated service bundled together. 
The template accepts the variables passed in from the resource. 

### Annotations

You will note that the manifests have annotations that are volterra specific. 
These are documented [here](https://www.volterra.io/docs/reference/vks-api-comp#resource-management-for-volterra-vk8s)

The annotations I am using, define a pod size, but also (and more importantly) a site to deploy to.
Think of a site as "where". 
In my case I am using a virtual site. As per the resources above, my virtual site uses a selector of **real** site names to aggregate all of my sites together. 

This allows me to have a deployment that is conducted / deployed at all sites at the same time.


```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: svk-swapi-api
  namespace: ${namespace}
  labels:
    app: ${manifest_app_name}
  annotations:
    ves.io/workload-flavor: tiny
    ves.io/virtual-sites: ${namespace}/${namespace}-vs
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${manifest_app_name}
  template:
    metadata:
      labels:
        app: ${manifest_app_name}
    spec:
      containers:
      - image: public.ecr.aws/y6q2t0j9/demos:swapi-api
        imagePullPolicy: IfNotPresent
        name: ${manifest_app_name}
        ports:
          - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: ${servicename}
  labels:
    app: ${manifest_app_name}
spec:
  type: ClusterIP
  selector:
    app: ${manifest_app_name}
  ports:
  - name: grpc
    port: 3000
    targetPort: 3000
```

The second template is deployment for the loadgen container.

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${loadgen_manifest_app_name}
  namespace: ${namespace}
  labels:
    app: ${loadgen_manifest_app_name}
  annotations:
    ves.io/workload-flavor: tiny
    ves.io/virtual-sites: ${namespace}/${namespace}-vs
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${loadgen_manifest_app_name}
  template:
    metadata:
      labels:
        app: ${loadgen_manifest_app_name}
    spec:
      containers:
      - image: public.ecr.aws/y6q2t0j9/demos:swapi-loadgen
        imagePullPolicy: IfNotPresent
        name: ${loadgen_manifest_app_name}
        ports:
          - containerPort: 8080
        env:
          - name: TARGET_URL
            value: "https://${manifest_app_name}.${domain}"
```

The main difference is that this container takes an environment variable that is the URL of the endpoint that you want to test. The container is built to use the tor network to generate a more random source address.
