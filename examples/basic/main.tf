terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

variable "integration_id" {
  type = string
}

variable "formal_role_arn" {
  type = string
}

variable "project_id" {
  type = string
}

module "formal_integration" {
  source = "../../"

  integration_id  = var.integration_id
  formal_role_arn = var.formal_role_arn
  project_id      = var.project_id
}

output "service_account_email" {
  value = module.formal_integration.service_account_email
}

output "workload_identity_pool_provider" {
  value = module.formal_integration.workload_identity_pool_provider
}
