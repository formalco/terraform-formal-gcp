terraform {
  required_version = ">= 1.3"

  # Configured by setup.sh; ignored when this repo is used as a child module.
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}
