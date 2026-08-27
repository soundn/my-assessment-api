variable "name" {
  description = "Environment resource prefix, e.g. cor-staging."
  type        = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "APP_ENV value: staging or production."
  type        = string
}

variable "image" {
  description = "Initial container image; CI/CD owns subsequent rollouts."
  type        = string
}

variable "subnet_cidr" {
  type = string
}

variable "psa_range_start" {
  type = string
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

variable "db_availability_type" {
  type    = string
  default = "ZONAL"
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "deployer_email" {
  type = string
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 4
}

variable "notification_email" {
  type = string
}
