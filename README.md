# Terraform Formal GCP

Connect a Google Cloud project to [Formal](https://joinformal.com) using Workload Identity Federation.

## What it does

This module lets Formal Control Plane federate into your Google Cloud project by presenting its AWS identity, which GCP trusts through a workload identity pool. Formal Control Plane can then impersonates a dedicated service account scoped to your project.

In your project, it enables the required APIs (IAM, STS, IAM credentials, Cloud Resource Manager) and then creates:

- a workload identity pool;
- an AWS-type workload identity pool provider that trusts Formal's AWS account and pins Formal's per-integration role ARN via an attribute condition (only that exact role can exchange a token);
- a service account for Formal to impersonate;
- an IAM binding on that service account granting the pool's principal set permission to impersonate it;
- project IAM bindings granting the service account the roles you pass in `roles`.

No keys are created. Access is entirely federated.

## Inputs

| Variable          | Description                                                                                                       |
| ---               | ---                                                                                                               |
| `integration_id`  | Formal Cloud Integration id.                                                                                      |
| `project_id`      | Google Cloud project id to connect.                                                                               |
| `formal_role_arn` | AWS IAM role ARN Formal presents for your cloud integration.                                                      |
| `roles`           | IAM roles to grant Formal's service account on the project, driven by the capabilities you enable (default `[]`). |

## Outputs

| Output                            | Description                                                                                                                   |
| ---                               | ---                                                                                                                           |
| `service_account_email`           | Email of the service account Formal impersonates.                                                                             |
| `workload_identity_pool_provider` | Full provider resource name (`projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<pool>/providers/<provider>`). |

## Usage

### Via Formal Console

Formal Console shows the exact command, with every argument filled in, when you create the GCP integration. Paste it into an authenticated Cloud Shell for the project:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/formalco/terraform-formal-gcp/main/setup.sh) \
  <integration_id> <project_id> <formal_role_arn> [role...]
```

It runs `terraform apply`, then reports the created service account and provider back to Formal, which activates the integration.

### With the Formal Terraform provider

Register the integration, provision the GCP resources with this module, then report them back to activate it:

```hcl
resource "formal_integration_cloud" "gcp" {
  name = "my-gcp"

  gcp {
    project_id = "my-gcp-project"
  }
}

module "formal_gcp" {
  source = "github.com/formalco/terraform-formal-gcp"

  integration_id  = formal_integration_cloud.gcp.id
  formal_role_arn = formal_integration_cloud.gcp.aws_formal_role_arn
  project_id      = "my-gcp-project"
  roles           = ["roles/cloudasset.viewer"]
}

resource "formal_integration_cloud_gcp_activation" "gcp" {
  integration_id                  = formal_integration_cloud.gcp.id
  service_account_email           = module.formal_gcp.service_account_email
  workload_identity_pool_provider = module.formal_gcp.workload_identity_pool_provider
}
```

The activation resource is separate from `formal_integration_cloud` on purpose: that resource feeds the module its id and role ARN, so reading the module outputs back into it would create a dependency cycle.
