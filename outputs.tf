output "service_account_email" {
  description = "Email of the service account Formal impersonates."
  value       = google_service_account.this.email
}

output "workload_identity_pool_provider" {
  description = "Full resource name of the workload identity pool provider, reported back to Formal."
  value       = google_iam_workload_identity_pool_provider.this.name
}
