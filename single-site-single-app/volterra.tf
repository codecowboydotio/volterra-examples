provider "volterra" {
#  api_p12_file     = "/root/f5-sa.console.ves.volterra.io.api-creds.p12"
#  url              = "https://f5-sa.console.ves.volterra.io/api"
  api_p12_file     = "/root/f5-sales-public.console.ves.volterra.io.api-creds.p12"
  url              = "https://f5-sales-public.console.ves.volterra.io/api"

}

resource "volterra_namespace" "ns" {
  name = var.ns
}

resource "time_sleep" "ns_wait" {
  depends_on = [volterra_namespace.ns]
  create_duration = "15s"
}


resource "volterra_virtual_site" "main" {
  name      = format("%s-vs", volterra_namespace.ns.name)
  namespace = volterra_namespace.ns.name
  depends_on = [time_sleep.ns_wait]

  labels = {
    "ves.io/siteName" = "svk-1"
  }
  site_selector {
    expressions = var.site_selector
  }
  site_type = "REGIONAL_EDGE"
}
resource "volterra_virtual_site" "svk2" {
  #name      = "svk-2-vs"
  name      = format("%s-2-vs", volterra_namespace.ns.name)
  namespace = volterra_namespace.ns.name
  depends_on = [time_sleep.ns_wait]

  labels = {
    "ves.io/siteName" = "svk-2"
  }
  site_selector {
    expressions = var.site_selector_svk2
  }
  site_type = "REGIONAL_EDGE"
}

resource "time_sleep" "vk8s_wait" {
  create_duration = "120s"
  depends_on = [volterra_virtual_site.main]
}


resource "volterra_virtual_k8s" "vk8s" {
  name      = format("%s-vk8s", volterra_namespace.ns.name)
  namespace = volterra_namespace.ns.name
  depends_on = [volterra_virtual_site.main]

  vsite_refs {
    name      = volterra_virtual_site.main.name
    namespace = volterra_namespace.ns.name
  }
}


resource "volterra_api_credential" "cred" {
  name      = format("%s-api-cred", var.manifest_app_name)
  api_credential_type = "KUBE_CONFIG"
  virtual_k8s_namespace = volterra_namespace.ns.name
  virtual_k8s_name = volterra_virtual_k8s.vk8s.name
}

resource "time_sleep" "vk8s_cred_wait" {
  create_duration = "30s"
  depends_on = [volterra_api_credential.cred]
}

resource "local_file" "kubeconfig" {
    content = base64decode(volterra_api_credential.cred.data)
    filename = format("%s/%s", path.module, format("%s-vk8s.yaml", terraform.workspace))

    depends_on = [time_sleep.vk8s_cred_wait]
}

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
    enable_path_normalize = true
  }
#  http {
#    dns_volterra_managed = true
#  }
  more_option {
    response_headers_to_add {
        name   = "Access-Control-Allow-Origin"
        value  = "*"
        append = false
    }
  }

  multi_lb_app                    = true 
  disable_waf                     = true
  disable_rate_limit              = true
  round_robin                     = true
  service_policies_from_namespace = true
  no_challenge                    = true
  user_id_client_ip = true
}

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

output "domain" { value = "${var.manifest_app_name}.${var.domain}" }
