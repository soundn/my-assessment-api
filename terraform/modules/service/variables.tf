variable "name" {
  description = "Cloud Run service name, e.g. cor-staging."
  type        = string
}

variable "region" {
  type = string
}

variable "environment" {
  description = "Value for APP_ENV (staging or production)."
  type        = string
}

variable "image" {
  description = "Initial container image. Subsequent image rollouts are performed by CI/CD and ignored by Terraform."
  type        = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password_secret_id" {
  type = string
}

variable "deployer_email" {
  description = "Service account used by CI/CD to deploy revisions."
  type        = string
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  type    = number
  default = 4
}

variable "cpu" {
  type    = string
  default = "1"
}

variable "memory" {
  type    = string
  default = "512Mi"
}

variable "log_level" {
  type    = string
  default = "info"
}

variable "allow_unauthenticated" {
  description = "Expose the API publicly. The assessment API is unauthenticated by design."
  type        = bool
  default     = true
}
