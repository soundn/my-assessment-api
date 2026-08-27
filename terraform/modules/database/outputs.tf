output "private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "database_name" {
  value = google_sql_database.app.name
}

output "database_user" {
  value = google_sql_user.app.name
}

output "password_secret_id" {
  description = "Secret Manager secret holding the database password."
  value       = google_secret_manager_secret.db_password.secret_id
}
