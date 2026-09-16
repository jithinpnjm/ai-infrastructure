# Ansible secret boundary

This directory is intentionally kept free of secret material in Git.

For the lab, the MUNGE key is supplied out-of-band on the Ansible controller at:

```text
phase-03/ansible/secrets/munge.key
```

The `.key` file is ignored by the repository-wide `.gitignore`.

Before running `playbooks/gpu-node.yml`, copy the trusted MUNGE key from the
existing Slurm controller into this path and verify its permissions locally.
Do not paste the key into YAML, commit history, issue comments, or chat.

Later phases may replace this controller-local secret boundary with Ansible
Vault or an external secret manager once the operational model requires it.
