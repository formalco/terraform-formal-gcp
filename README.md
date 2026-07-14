# Terraform Formal GCP

Connect a Google Cloud project to [Formal](https://joinformal.com) using Workload Identity Federation.

## What it does

This module lets Formal Control Plane federate into your Google Cloud project by presenting its AWS identity, which GCP trusts through a workload identity pool. Formal Control Plane can then impersonates a dedicated service account scoped to your project.

In your project, it enables the required APIs (IAM, STS, IAM credentials, Cloud Resource Manager) and then creates:

- a workload identity pool;
- an AWS-type workload identity pool provider that trusts Formal's AWS account and pins Formal's per-integration role ARN via an attribute condition (only that exact role can exchange a token);
- a service account for Formal to impersonate;
- an IAM binding on that service account granting the pool's principal set permission to impersonate it;
- project IAM bindings granting the service account the roles you pass in `roles`;
- per-bucket IAM bindings granting `roles/storage.objectCreator` on each bucket in `gcs_buckets`, for log delivery.

No keys are created. Access is entirely federated.

## Inputs

| Variable          | Description                                                                                                       |
| ---               | ---                                                                                                               |
| `integration_id`  | Formal Cloud Integration id.                                                                                      |
| `project_id`      | Google Cloud project id to connect.                                                                               |
| `formal_role_arn` | AWS IAM role ARN Formal presents for your cloud integration.                                                      |
| `roles`           | IAM roles to grant Formal's service account on the project, driven by the capabilities you enable (default `[]`). |
| `gcs_buckets`     | GCS buckets Formal may write logs to; each is granted object-create access. Empty disables log delivery (default `[]`). |

## Outputs

| Output                            | Description                                                                                                                   |
| ---                               | ---                                                                                                                           |
| `service_account_email`           | Email of the service account Formal impersonates.                                                                             |
| `workload_identity_pool_provider` | Full provider resource name (`projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`). |

## Usage

### Via Formal Console

Formal Console shows the exact command, with the id and security key filled in, when you create the GCP integration. Paste it into an authenticated Cloud Shell for the project:

```bash
bash <(curl -sSL https://formal.ai/gcp.sh) \
  <integration_id> <security_key>
```

It fetches the setup parameters from Formal, runs `terraform apply`, then reports the created service account and provider back to Formal, which activates the integration.

To change access later (for example after enabling or disabling resource discovery or log delivery on the integration), change the capability on the integration in Formal, then run the same command again. The script keeps its Terraform state in a bucket in your project, so a rerun reconciles the granted roles both ways: it adds what the integration now needs and removes what it no longer does.

State is stored as `<integration_id>.tfstate` in a single-region Standard bucket named `fml-<suffix>`, created in the region set by `STATE_BUCKET_LOCATION` (default `us-central1`).

### With the Formal Terraform provider

Register the integration, provision the GCP resources with this module, then report them back to activate it:

```hcl
resource "formal_integration_cloud" "gcp" {
  name = "my-gcp"

  gcp {
    project_id                              = "my-gcp-project"
    enable_compute_instances_autodiscovery  = true
    enable_gke_clusters_autodiscovery       = true
    enable_cloudsql_instances_autodiscovery = true
  }
}

module "formal_gcp" {
  source = "github.com/formalco/terraform-formal-gcp"

  integration_id  = formal_integration_cloud.gcp.id
  formal_role_arn = formal_integration_cloud.gcp.aws_formal_role_arn
  project_id      = "my-gcp-project"
  roles           = formal_integration_cloud.gcp.gcp_roles
  gcs_buckets     = formal_integration_cloud.gcp.gcp_gcs_buckets
}

resource "formal_integration_cloud_gcp_activation" "gcp" {
  integration_id                  = formal_integration_cloud.gcp.id
  service_account_email           = module.formal_gcp.service_account_email
  workload_identity_pool_provider = module.formal_gcp.workload_identity_pool_provider
}
```

`roles` and `gcs_buckets` come from the integration's computed attributes, which Formal derives from the capabilities you enable on the `gcp` block. Pass them through so the module grants exactly what the integration needs.

The activation resource is separate from `formal_integration_cloud` on purpose: that resource feeds the module its id and role ARN, so reading the module outputs back into it would create a dependency cycle.
