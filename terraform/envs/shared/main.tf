terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  backend "gcs" {
    bucket = "cashonrails-assess-tfstate"
    prefix = "env/shared"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Container registry, shared by all environments. Images are immutable and
# promoted between environments by digest/tag rather than rebuilt.
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "docker" {
  repository_id = "cashonrails"
  format        = "DOCKER"
  location      = var.region
  description   = "Application images for the assessment API"
}

# ---------------------------------------------------------------------------
# Keyless CI/CD identity: GitHub Actions authenticates via OIDC federation.
# No long-lived service account keys exist anywhere in this setup.
# ---------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only workflows from this repository can exchange tokens.
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions deployer"
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Project-level grants for the deployer. The project contains only this
# workload, so the project is the blast-radius boundary; in a shared or org
# setting these would be per-resource grants.
resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.admin",               # deploy revisions, run migration jobs
    "roles/artifactregistry.writer", # push images
    "roles/viewer",                  # terraform plan in CI
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_storage_bucket_iam_member" "deployer_state" {
  bucket = "cashonrails-assess-tfstate"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}
