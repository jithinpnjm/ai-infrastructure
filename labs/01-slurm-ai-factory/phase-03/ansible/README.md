# Phase 03 Ansible

This directory contains the configuration-management layer for GPU worker onboarding.

## Current state

Phase 03 is being built incrementally. The first commit establishes the Ansible execution defaults and lab inventory model without provisioning or modifying any GPU worker.

```text
ansible/
├── ansible.cfg
├── inventories/
│   └── lab/
│       ├── hosts.yml
│       └── group_vars/
│           └── all.yml
├── playbooks/       # added as implementation progresses
└── roles/           # added as implementation progresses
```

## Architectural rules

- Nebius provisions the VM, GPU, network and storage.
- Ansible configures the operating system and GPU worker software stack.
- Slurm controls resource allocation and workload scheduling.
- Inventory describes hosts and topology; roles describe desired state.
- Secrets are never committed to Git.
- Hardware-specific values must be verified against the actual node rather than blindly trusted from a cloud preset.
- Validation is a first-class part of convergence; a successful playbook run alone is not acceptance.

## Lab target

The next compute stage will use two Nebius L40S workers:

```text
                 slurm-controller-01
                       10.0.0.4
                           │
                    Slurm / MUNGE
                           │
              ┌────────────┴────────────┐
              │                         │
        l40-node-01               l40-node-02
          L40S × 1                  L40S × 1
```

The actual worker addresses will be added only after the Phase 04 VMs are provisioned and their network identity is verified.

## Next implementation step

Create the Ansible role skeleton and define the execution order:

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

The MUNGE secret-handling mechanism must be settled before the `munge` role is implemented.
