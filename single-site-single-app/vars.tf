variable "ns" { default = "s-vankalken" }
#variable "domain" { default = "sa.f5demos.com" }
variable "domain" { default = "sales-public.f5demos.com" }
variable "servicename" { default = "svk-swapi-api" }

variable "manifest_app_name" { default = "svk-swapi-api" }
variable "loadgen_manifest_app_name" { default = "svk-swapi-loadgen" }

#variable "site_selector" { default = [ "ves.io/siteName in (ves-io-sg3-sin, ves-io-ny8-nyc, ves-io-os1-osa)" ] }
variable "site_selector" { default = [ "ves.io/siteName in (ves-io-me1-mel, ves-io-sy5-syd)" ] }
variable "site_selector_svk2" { default = [ "ves.io/siteName in (ves-io-sg3-sin)" ] }
