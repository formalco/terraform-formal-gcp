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

REPO_URL="https://github.com/formalco/terraform-formal-gcp.git"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If setup.sh was piped/curled rather than run from a checkout, clone the repo.
if [[ ! -f "${WORKDIR}/main.tf" ]]; then
  WORKDIR="$(mktemp -d)/terraform-formal-gcp"
  git clone --depth 1 "${REPO_URL}" "${WORKDIR}"
fi

cd "${WORKDIR}"

terraform init -input=false
terraform apply -input=false -auto-approve \
  -var "integration_id=${INTEGRATION_ID}" \
  -var "project_id=${PROJECT_ID}" \
  -var "formal_role_arn=${FORMAL_ROLE_ARN}" \
  -var "roles=${ROLES}"

SERVICE_ACCOUNT_EMAIL="$(terraform output -raw service_account_email)"
WORKLOAD_IDENTITY_POOL_PROVIDER="$(terraform output -raw workload_identity_pool_provider)"

curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/SetGCPCloudIntegrationActivation" \
  -H "Content-Type: application/json" \
  -d "$(cat <<JSON
{"id":"${INTEGRATION_ID}","securityKey":"${SECURITY_KEY}","serviceAccountEmail":"${SERVICE_ACCOUNT_EMAIL}","workloadIdentityPoolProvider":"${WORKLOAD_IDENTITY_POOL_PROVIDER}"}
JSON
)"

echo
echo "Done. Formal is now connected to project ${PROJECT_ID}."
