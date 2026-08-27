locals {
  # Environment shared by the API service and the migration job.
  common_env = {
    APP_NAME         = "CashOnRails Assessment API"
    APP_ENV          = var.environment
    APP_DEBUG        = "false"
    LOG_CHANNEL      = "stderr"
    LOG_LEVEL        = var.log_level
    DB_CONNECTION    = "mysql"
    DB_HOST          = var.db_host
    DB_PORT          = "3306"
    DB_DATABASE      = var.db_name
    DB_USERNAME      = var.db_user
    SESSION_DRIVER   = "database"
    CACHE_STORE      = "database"
    QUEUE_CONNECTION = "database"
  }

  secret_env = {
    APP_KEY     = google_secret_manager_secret.app_key.secret_id
    DB_PASSWORD = var.db_password_secret_id
  }
}

# Laravel APP_KEY: generated once here, never committed to source control.
resource "random_bytes" "app_key" {
  length = 32
}

resource "google_secret_manager_secret" "app_key" {
  secret_id = "${var.name}-app-key"

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "app_key" {
  secret      = google_secret_manager_secret.app_key.id
  secret_data = "base64:${random_bytes.app_key.base64}"
}

resource "google_service_account" "runtime" {
  account_id   = "${var.name}-run"
  display_name = "${var.name} Cloud Run runtime"
}

resource "google_secret_manager_secret_iam_member" "runtime_app_key" {
  secret_id = google_secret_manager_secret.app_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "runtime_db_password" {
  secret_id = var.db_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

# The CI deployer may deploy revisions that run as this identity, and nothing
# broader.
resource "google_service_account_iam_member" "deployer_uses_runtime" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_email}"
}

resource "google_cloud_run_v2_service" "api" {
  name     = var.name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"

      network_interfaces {
        network    = var.network_id
        subnetwork = var.subnet_id
      }
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secret_env
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      # /ready performs a database connectivity check, so the service only
      # receives traffic once it can reach Cloud SQL.
      startup_probe {
        http_get {
          path = "/api/v1/ready"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 12
        timeout_seconds       = 3
      }

      liveness_probe {
        http_get {
          path = "/api/v1/health"
          port = 8080
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  # Terraform owns service configuration; CI/CD owns image rollout.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.runtime_app_key,
    google_secret_manager_secret_iam_member.runtime_db_password,
    google_secret_manager_secret_version.app_key,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Migrations run as a separate job with the same image and identity, executed
# by CI before each deploy.
resource "google_cloud_run_v2_job" "migrate" {
  name     = "${var.name}-migrate"
  location = var.region

  template {
    template {
      service_account = google_service_account.runtime.email
      max_retries     = 1

      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"

        network_interfaces {
          network    = var.network_id
          subnetwork = var.subnet_id
        }
      }

      containers {
        image   = var.image
        command = ["php"]
        args    = ["artisan", "migrate", "--force"]

        dynamic "env" {
          for_each = local.common_env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.runtime_app_key,
    google_secret_manager_secret_iam_member.runtime_db_password,
    google_secret_manager_secret_version.app_key,
  ]
}
