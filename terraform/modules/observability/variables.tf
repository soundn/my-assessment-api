variable "name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "notification_email" {
  type = string
}

variable "service_url" {
  description = "Public URL of the Cloud Run service, used by the uptime check."
  type        = string
}

variable "service_name" {
  type = string
}

variable "sql_instance_name" {
  type = string
}
