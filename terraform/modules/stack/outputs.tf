output "service_url" {
  value = module.service.url
}

output "service_name" {
  value = module.service.service_name
}

output "migrate_job_name" {
  value = module.service.migrate_job_name
}

output "database_instance" {
  value = module.database.instance_name
}
