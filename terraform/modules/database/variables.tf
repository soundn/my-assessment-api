variable "name" {
  description = "Prefix for database resources, e.g. cor-staging."
  type        = string
}

variable "region" {
  type = string
}

variable "network_id" {
  description = "Self-link of the VPC the instance attaches to via private IP."
  type        = string
}

variable "psa_connection_id" {
  description = "ID of the private-services-access connection; enforces ordering."
  type        = string
}

variable "tier" {
  description = "Machine tier. Assessment default is the smallest shared-core tier; production would use a dedicated-core tier such as db-custom-2-8192."
  type        = string
  default     = "db-f1-micro"
}

variable "availability_type" {
  description = "ZONAL or REGIONAL (HA with automatic failover). REGIONAL requires a dedicated-core tier."
  type        = string
  default     = "ZONAL"
}

variable "disk_size_gb" {
  type    = number
  default = 10
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "database_name" {
  type    = string
  default = "app"
}

variable "database_user" {
  type    = string
  default = "app"
}
