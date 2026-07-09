locals {
  suffix = element(split("_", var.integration_id), length(split("_", var.integration_id)) - 1)
  name   = "fml-${local.suffix}"

  formal_aws_account_id = element(split(":", var.formal_role_arn), 4)
  formal_role_name      = element(split("/", var.formal_role_arn), length(split("/", var.formal_role_arn)) - 1)

  required_apis = [
    "iam.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "this" {
  project                   = var.project_id
  workload_identity_pool_id = local.name
  display_name              = local.name
  description               = "Formal cloud integration ${var.integration_id}"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "this" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.this.workload_identity_pool_id
  workload_identity_pool_provider_id = local.name
  display_name                       = local.name
  description                        = "Formal cloud integration ${var.integration_id}"

  # Only Formal's per-integration role may exchange a token. assertion.arn from
  # an AWS STS assumed-role identity looks like:
  #   arn:aws:sts::<account>:assumed-role/<role-name>/<session>
  # We pin the account and role name derived from the passed-in role ARN.
  attribute_condition = "attribute.aws_account == \"${local.formal_aws_account_id}\" && google.subject.startsWith(\"arn:aws:sts::${local.formal_aws_account_id}:assumed-role/${local.formal_role_name}/\")"

  attribute_mapping = {
    "google.subject"        = "assertion.arn"
    "attribute.aws_account" = "assertion.account"
    "attribute.aws_role"    = "assertion.arn"
  }

  aws {
    account_id = local.formal_aws_account_id
  }
}

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = local.name
  display_name = "Formal integration ${var.integration_id}"
  description  = "Impersonated by Formal via workload identity federation."

  depends_on = [google_project_service.this]
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.this.name
  role               = "roles/iam.workloadIdentityUser"
  # Any identity that federated through this pool may impersonate the account.
  # The pool provider's attribute_condition already restricts entry to Formal's role.
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.this.name}/*"
}

resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_storage_bucket_iam_member" "log_buckets" {
  for_each = toset(var.gcs_buckets)

  bucket = each.value
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.this.email}"
}
