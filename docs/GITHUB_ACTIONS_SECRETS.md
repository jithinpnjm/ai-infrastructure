# GitHub Actions credential model

## Principle

Use a dedicated Nebius service account for automation. Do not use a personal 12-hour IAM access token in GitHub Actions. Nebius recommends service-account authentication for Terraform/non-UI automation.

## Required for the first infrastructure workflows

### `NEBIUS_SA_ID`
Nebius service account ID used by Terraform/CLI automation.

### `NEBIUS_AUTHKEY_ID`
Nebius authorized public-key ID associated with the service account.

### `NEBIUS_AUTHKEY_PRIVATE_KEY`
The private key corresponding to the Nebius authorized key. Store the PEM contents as a GitHub Actions secret. Never commit it.

### `NEBIUS_PROJECT_ID`
Nebius project ID. This is configuration rather than a secret, so it may alternatively be a GitHub Actions variable.

### `SSH_PRIVATE_KEY`
Private SSH key used by Ansible to reach the provisioned Linux nodes, if the workflow uses direct SSH configuration. Store only the private key; the public key is installed on the VM through the infrastructure configuration.

## Later, only when required

### Nebius Object Storage / S3-compatible storage
If workflows directly use Object Storage through AWS-compatible APIs, create a dedicated service account access key and add:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

These are different from the Nebius authorized key used for Terraform. Do not confuse access keys with IAM access tokens or authorized keys.

## GitHub authentication

No personal GitHub PAT should be required for normal workflow execution. GitHub automatically provides `GITHUB_TOKEN` to each Actions job. Give it the minimum explicit permissions required by the workflow.

## Environment separation

When we introduce expensive GPU environments, use GitHub Environments such as `nebius-lab` and put production-impacting secrets there. This gives us a clean boundary for approvals and environment-specific credentials.

## Secret handling rules

- Never commit private keys, access tokens, passwords or cloud credentials.
- Never echo secrets in workflows.
- Do not put credentials in Terraform variables files committed to Git.
- Prefer short-lived or expiring credentials where the Nebius service supports them.
- Use a dedicated service account with only the permissions required by the lab.
- Keep Object Storage access separate from infrastructure-management credentials.
