variable "name" {
  description = "Prefix for network resources, e.g. cor-staging."
  type        = string
}

variable "region" {
  description = "Region for the application subnet."
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the application subnet."
  type        = string
}

variable "psa_range_start" {
  description = "First address of the reserved private-services-access range."
  type        = string
}

variable "psa_prefix_length" {
  description = "Prefix length of the reserved private-services-access range."
  type        = number
  default     = 20
}
