variable "ns" { default = "s-vankalken" }
#variable "domain" { default = "sa.f5demos.com" }
variable "domain" { default = "sales-public.f5demos.com" }
variable "servicename" { default = "svk-swapi-api2" }

variable "manifest_app_name" { default = "svk-swapi-api2" }
variable "loadgen_manifest_app_name" { default = "svk-swapi-loadgen2" }

variable "site_selector" { default = [ "ves.io/siteName in (ves-io-sg3-sin, ves-io-ny8-nyc, ves-io-os1-osa)" ] }
