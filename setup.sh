#!/usr/bin/env bash
#
# Connect a Google Cloud project to Formal via Workload Identity Federation.
#
# Run this inside an authenticated Google Cloud Shell for the project you want
# to connect. It applies the Terraform in this repo, then reports the created
# service account and workload identity pool provider back to Formal, which
# activates the integration. Formal shows the exact command (with all arguments
# filled in) when you create the GCP integration.
#
# Usage:
#   ./setup.sh <integration_id> <project_id> <formal_role_arn> <formal_api_url> [role...]
#
# Any arguments after formal_api_url are IAM roles to grant Formal's service
# account on the project (e.g. roles/cloudasset.viewer roles/storage.objectViewer).
# Pass none to establish the connection with no project access.

set -euo pipefail

INTEGRATION_ID="${1:-}"
PROJECT_ID="${2:-}"
FORMAL_ROLE_ARN="${3:-}"
FORMAL_API_URL="${4:-}"

if [[ -z "${INTEGRATION_ID}" || -z "${PROJECT_ID}" || -z "${FORMAL_ROLE_ARN}" || -z "${FORMAL_API_URL}" ]]; then
  echo "Usage: $0 <integration_id> <project_id> <formal_role_arn> <formal_api_url> [role...]" >&2
  exit 1
fi
shift 4
ROLES=("$@")

# Build a Terraform list literal from the role arguments; empty stays [].
ROLES_TF="[]"
if [[ ${#ROLES[@]} -gt 0 ]]; then
  printf -v roles_joined '"%s",' "${ROLES[@]}"
  ROLES_TF="[${roles_joined%,}]"
fi

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
  -var "roles=${ROLES_TF}"

SERVICE_ACCOUNT_EMAIL="$(terraform output -raw service_account_email)"
WORKLOAD_IDENTITY_POOL_PROVIDER="$(terraform output -raw workload_identity_pool_provider)"

# Report the created resources back to Formal, which activates the integration.
curl -fsS -X POST \
  "${FORMAL_API_URL%/}/core.v1.IntegrationCloudService/SetGCPCloudIntegrationActivation" \
  -H "Content-Type: application/json" \
  -d "$(cat <<JSON
{"id":"${INTEGRATION_ID}","serviceAccountEmail":"${SERVICE_ACCOUNT_EMAIL}","workloadIdentityPoolProvider":"${WORKLOAD_IDENTITY_POOL_PROVIDER}"}
JSON
)"

echo
echo "Done. Formal is now connected to project ${PROJECT_ID}."
