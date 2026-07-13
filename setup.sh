#!/usr/bin/env bash
#
# Connect a Google Cloud project to Formal via Workload Identity Federation.
#
# Run this inside an authenticated Google Cloud Shell for the project you want
# to connect. It fetches the integration parameters from Formal, applies the
# Terraform in this repo, then reports the created service account and workload
# identity pool provider back to Formal, which activates the integration. Formal
# shows the exact command when you create the GCP integration.
#
# Usage:
#   ./setup.sh <integration_id> <security_key>
#
# FORMAL_API_URL defaults to production; override it for other environments.

set -euo pipefail

INTEGRATION_ID="${1:-}"
SECURITY_KEY="${2:-}"
FORMAL_API_URL="${FORMAL_API_URL:-https://api.joinformal.com}"

if [[ -z "${INTEGRATION_ID}" || -z "${SECURITY_KEY}" ]]; then
  echo "Usage: $0 <integration_id> <security_key>" >&2
  exit 1
fi

SETUP="$(curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/GetGCPCloudIntegrationSetup" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"${INTEGRATION_ID}\",\"securityKey\":\"${SECURITY_KEY}\"}")"

PROJECT_ID="$(jq -r '.projectId' <<<"${SETUP}")"
FORMAL_ROLE_ARN="$(jq -r '.formalRoleArn' <<<"${SETUP}")"
ROLES="$(jq -c '.roles // []' <<<"${SETUP}")"
GCS_BUCKETS="$(jq -c '.gcsBuckets // []' <<<"${SETUP}")"

REPO_URL="https://github.com/formalco/terraform-formal-gcp.git"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If setup.sh was piped/curled rather than run from a checkout, clone the repo.
if [[ ! -f "${WORKDIR}/main.tf" ]]; then
  WORKDIR="$(mktemp -d)/terraform-formal-gcp"
  git clone --depth 1 "${REPO_URL}" "${WORKDIR}"
fi

cd "${WORKDIR}"

# Fetch terraform binary when the real one isn't already on PATH.
TERRAFORM=terraform
if ! terraform version 2>/dev/null | grep -q '^Terraform v'; then
  TF_VERSION="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)"
  TF_ARCH="$(uname -m)"
  case "${TF_ARCH}" in
    x86_64) TF_ARCH=amd64 ;;
    aarch64 | arm64) TF_ARCH=arm64 ;;
  esac
  TF_DIR="$(mktemp -d)"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip" -o "${TF_DIR}/terraform.zip"
  unzip -q -o "${TF_DIR}/terraform.zip" -d "${TF_DIR}"
  TERRAFORM="${TF_DIR}/terraform"
fi

TF_VARS=(
  -var "integration_id=${INTEGRATION_ID}"
  -var "project_id=${PROJECT_ID}"
  -var "formal_role_arn=${FORMAL_ROLE_ARN}"
  -var "roles=${ROLES}"
  -var "gcs_buckets=${GCS_BUCKETS}"
)

# Keep Terraform state in a bucket in this project so reruns reconcile access
# both ways instead of starting blank. Override the region with
# STATE_BUCKET_LOCATION; versioning allows rolling back a bad apply.
STATE_BUCKET="fml-${INTEGRATION_ID##*_}-tfstate"
STATE_BUCKET_LOCATION="${STATE_BUCKET_LOCATION:-us-central1}"

if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="${PROJECT_ID}" \
    --location="${STATE_BUCKET_LOCATION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
fi

"${TERRAFORM}" init -input=false \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=${INTEGRATION_ID}"

"${TERRAFORM}" apply -input=false -auto-approve "${TF_VARS[@]}"

SERVICE_ACCOUNT_EMAIL="$("${TERRAFORM}" output -raw service_account_email)"
WORKLOAD_IDENTITY_POOL_PROVIDER="$("${TERRAFORM}" output -raw workload_identity_pool_provider)"

curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/SetGCPCloudIntegrationActivation" \
  -H "Content-Type: application/json" \
  -d "$(cat <<JSON
{"id":"${INTEGRATION_ID}","securityKey":"${SECURITY_KEY}","serviceAccountEmail":"${SERVICE_ACCOUNT_EMAIL}","workloadIdentityPoolProvider":"${WORKLOAD_IDENTITY_POOL_PROVIDER}"}
JSON
)"

echo
echo "Done. Formal is now connected to project ${PROJECT_ID}."
