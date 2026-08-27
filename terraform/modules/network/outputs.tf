output "network_id" {
  value = google_compute_network.vpc.id
}

output "subnet_id" {
  value = google_compute_subnetwork.app.id
}

output "psa_connection_id" {
  description = "Used to sequence resources that require the PSA peering."
  value       = google_service_networking_connection.psa.id
}
