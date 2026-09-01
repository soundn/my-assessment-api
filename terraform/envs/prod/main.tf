terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "gcs" {
    bucket = "cashonrails-live-tfstate"
    prefix = "env/prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "stack" {
  source = "../../modules/stack"

  name        = "cor-prod"
  project_id  = var.project_id
  region      = var.region
  environment = "production"
  image       = var.image

  subnet_cidr     = "10.70.0.0/24"
  psa_range_start = "10.71.0.0"

  db_tier                = var.db_tier
  db_availability_type   = var.db_availability_type
  db_deletion_protection = var.db_deletion_protection

  deployer_email     = var.deployer_email
  min_instances      = var.min_instances
  max_instances      = var.max_instances
  notification_email = var.notification_email
}
