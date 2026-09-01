variable "project_id" {
  type    = string
  default = "cashonrails-live"
}

variable "region" {
  type    = string
  default = "africa-south1"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to authenticate via OIDC."
  type        = string
  default     = "soundn/my-assessment-api"
}
