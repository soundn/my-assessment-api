output "url" {
  value = google_cloud_run_v2_service.api.uri
}

output "service_name" {
  value = google_cloud_run_v2_service.api.name
}

output "migrate_job_name" {
  value = google_cloud_run_v2_job.migrate.name
}

output "runtime_service_account" {
  value = google_service_account.runtime.email
}
