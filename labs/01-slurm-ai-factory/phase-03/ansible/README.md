# Phase 03 Ansible

This directory contains the configuration-management layer for GPU worker onboarding.

## Current state

The Ansible implementation is now complete enough to be reviewed and syntax-validated **without provisioning or modifying a GPU VM**.

```text
ansible/
├── ansible.cfg
├── requirements.yml
├── inventories/
│   └── lab/
│       ├── hosts.yml
│       └── group_vars/
│           ├── all.yml
│           └── gpu_workers.yml
├── playbooks/
│   ├── gpu-node.yml
│   └── validate-gpu-node.yml
├── roles/
│   ├── base/
│   ├── nvidia/
│   ├── munge/
│   ├── slurm/
│   └── validation/
└── secrets/
    └── README.md
```

## Execution order

```text
base
  ↓
nvidia
  ↓
munge
  ↓
slurm
  ↓
validation
```

The roles intentionally separate generic OS preparation, GPU validation, cluster authentication, Slurm worker configuration and acceptance testing.

## What is automated

### Base

- common packages
- timezone
- systemd presence
- cgroup v2 prerequisite

### NVIDIA

- optional package installation, disabled by default for the Nebius preconfigured GPU image
- `nvidia-smi` GPU count/model validation
- optional `nvcc` visibility check

The role does not blindly replace a vendor-provided driver.

### MUNGE

- package installation
- trusted cluster key deployment
- ownership and mode enforcement
- service state
- local encode/decode validation

The MUNGE key is supplied out-of-band from the Ansible controller. It is never stored in Git.

### Slurm

- worker packages
- spool/log directories
- `slurm.conf`
- `gres.conf` with NVML discovery
- cgroup configuration
- `slurmd -C` validation
- `slurmd -G` validation
- service state

The generated worker configuration describes all hosts in the `gpu_workers` inventory group so the workers share a consistent node view.

### Validation

Standalone validation checks:

- NVIDIA device node
- cgroup v2
- MUNGE service
- Slurm service
- GRES detection
- optional controller reachability
- optional CUDA compiler

Controller registration and real GPU-job validation remain runtime acceptance tests and require actual infrastructure.

## Secrets

Do not commit the MUNGE key. The expected controller-local path is:

```text
phase-03/ansible/secrets/munge.key
```

The repository-wide `.gitignore` excludes `*.key` files.

## Static validation without a GPU VM

Run from the repository root:

```bash
bash labs/01-slurm-ai-factory/phase-03/tools/validate-ansible.sh
```

If `ansible-playbook` is installed, the script also runs syntax checks for both playbooks. Otherwise it performs the structural checks and clearly reports that syntax validation was skipped.

## Runtime boundary

No GPU VM is required to build or review this code.

When Phase 04 eventually provisions the two L40S workers, inventory will be populated with their verified addresses and hardware facts. The first runtime execution will then be a controlled convergence test, followed by idempotency and Slurm registration validation.
