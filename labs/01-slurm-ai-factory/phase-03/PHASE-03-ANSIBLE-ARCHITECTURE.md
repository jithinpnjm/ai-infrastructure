# Phase 03 — Ansible Architecture

## Objective

Design and implement a production-shaped Ansible configuration-management layer for onboarding GPU compute nodes into the AI factory.

The objective is not simply to automate package installation. The objective is to make a fresh GPU node reproducibly and idempotently converge to a validated Slurm worker:

```text
Fresh GPU VM
    ↓
Ansible
    ↓
OS / prerequisites
    ↓
NVIDIA + CUDA
    ↓
MUNGE
    ↓
Slurm + GRES
    ↓
cgroup v2
    ↓
Validation
    ↓
Slurm IDLE
```

## Why This Phase Exists

Phase 01 deliberately used manual configuration to understand the GPU-node stack. Manual work was valuable for learning the relationship between the NVIDIA driver, CUDA, MUNGE, Slurm, GRES and cgroup v2, but it is not an acceptable operational model for repeatedly onboarding production GPU nodes.

Phase 03 turns that learned configuration into a reproducible desired state.

The goal is to be able to destroy a worker and rebuild it from the documented configuration without depending on undocumented shell history or one-off fixes.

## Architectural Boundary

Cloud provisioning, configuration management and workload orchestration are deliberately separate concerns.

### Cloud provisioning

Nebius is responsible for creating and exposing the infrastructure:

- VM
- GPU attachment
- network interfaces
- storage
- SSH access
- cloud-level lifecycle

### Configuration management

Ansible is responsible for the state inside the VM:

- operating-system prerequisites
- NVIDIA validation/configuration
- CUDA
- MUNGE
- Slurm worker
- GRES
- cgroup v2
- service configuration
- validation

### Workload orchestration

Slurm is responsible for:

- resource allocation
- job scheduling
- CPU and memory allocation
- GPU allocation
- accounting integration

Keeping these boundaries explicit prevents a single automation layer from becoming responsible for the entire platform.

## Why Ansible

A GPU worker is a dependency chain rather than a collection of unrelated packages:

```text
GPU / PCIe exposure
        ↓
NVIDIA driver
        ↓
CUDA runtime/toolkit
        ↓
MUNGE trust/authentication
        ↓
Slurm daemon
        ↓
GRES GPU resource definition
        ↓
cgroup v2 resource/device enforcement
```

A change at one layer can affect another. Ansible gives us a declarative, repeatable mechanism to converge a fresh node toward the desired state and to detect configuration drift.

## Production Model

A company may have many GPU nodes. The automation should therefore be based on **roles and inventory**, not on individual host names.

For example:

```text
                  Ansible Controller
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
      GPU node 01    GPU node 02    GPU node N
          │              │              │
       same role      same role      same role
          │              │              │
          └──────────────┴──────────────┘
                         │
                   Slurm cluster
```

Host-specific differences should be represented as inventory variables rather than copied playbooks.

## Planned Repository Structure

The structure will be introduced incrementally so every directory and role has a documented purpose.

```text
phase-03/
├── PHASE-03-ANSIBLE-ARCHITECTURE.md
└── ansible/
    ├── ansible.cfg
    ├── inventories/
    │   └── lab/
    │       ├── hosts.yml
    │       └── group_vars/
    ├── playbooks/
    │   ├── gpu-node.yml
    │   └── validate-gpu-node.yml
    └── roles/
        ├── base/
        ├── nvidia/
        ├── munge/
        ├── slurm/
        └── validation/
```

This is a target structure, not a requirement to create empty directories immediately.

## Roles and Responsibilities

### `base`

Owns generic worker prerequisites such as packages, users, directories and operating-system settings that are genuinely common to all GPU workers.

It should not contain NVIDIA- or Slurm-specific logic.

### `nvidia`

Owns validation and, where required, configuration of the NVIDIA driver/CUDA layer.

The role must verify the actual GPU rather than assuming that package installation means the GPU is usable.

Examples of validation include:

```bash
nvidia-smi
nvidia-smi -L
nvcc --version
```

### `munge`

Owns MUNGE installation, key deployment, permissions and service state.

The MUNGE key is a secret and must never be committed to Git.

### `slurm`

Owns the worker-side Slurm configuration and `slurmd` service.

Controller configuration remains a separate concern.

### `validation`

Provides explicit post-convergence checks. A successful Ansible run is not itself proof that the GPU worker is operational.

Validation should eventually cover:

- NVIDIA device visibility
- CUDA
- MUNGE encode/decode
- `slurmd`
- `slurmd -G`
- cgroup v2
- controller registration
- Slurm GPU allocation

## Inventory Design

Inventory describes **what infrastructure exists** and how Ansible reaches it.

Example conceptual grouping:

```yaml
gpu_workers:
  hosts:
    l40-node-01:
    l40-node-02:
```

The actual inventory will contain connection details appropriate to the lab while avoiding hard-coded secrets.

Inventory should describe topology and host identity; roles should describe desired state.

## Variables

Variables will separate reusable logic from environment-specific values.

Examples include:

- Slurm cluster name
- controller address
- Slurm ports
- GPU type
- expected GPU count
- expected CPU count
- expected memory
- package versions where pinning is justified

A value should be variable-driven when it is legitimately environment- or hardware-specific. We should not turn every constant into a variable merely for the sake of abstraction.

## Secrets Boundary

Secrets must not be stored in plain text in the repository.

Examples:

- MUNGE key
- database credentials
- private SSH material

The exact secret-management mechanism will be selected before implementation. For the lab, the important architectural requirement is that Git contains the configuration and references, not secret material.

## Idempotency

Running the same playbook twice should converge to the same state rather than repeatedly modifying the machine.

For example:

```text
First run  → changed resources
Second run → ideally changed=0
```

However, `changed=0` is not sufficient validation. The resulting system must still be tested from the operating-system and Slurm perspectives.

## Validation Philosophy

Every major layer should have a validation gate.

Examples:

```text
NVIDIA
  → nvidia-smi

CUDA
  → nvcc / CUDA workload validation

MUNGE
  → munge -n | unmunge

Slurm worker
  → systemctl / slurmd

GRES
  → slurmd -G

cgroup
  → /sys/fs/cgroup inspection

Cluster
  → sinfo / scontrol

Workload
  → actual Slurm GPU job
```

The final workload test is particularly important because it proves the complete chain rather than individual components in isolation.

## Failure and Recovery Model

For each major automation stage we will eventually document:

1. expected state
2. failure mode
3. observable symptom
4. diagnostic command
5. remediation
6. recovery validation

We will not invent failure behavior. Failure scenarios will be tested against real infrastructure when the relevant nodes exist.

## Rebuildability

The final Phase 03 implementation should allow a fresh GPU VM to be configured without repeating the manual Phase 01 procedure.

Expensive compute resources should remain easy to destroy and recreate. Persistent low-cost artifacts such as Git configuration and other deliberately retained state should provide the rebuild source of truth.

The manually configured Phase 01 `l40-node-01` was intentionally deleted and must not be recreated merely for this phase.

## Explicitly Deferred

The following are outside the initial Phase 03 implementation:

- Nebius VM provisioning automation
- Terraform
- GitHub Actions automation
- distributed training
- NCCL
- InfiniBand
- NVLink/NVSwitch
- Kubernetes
- Run:ai
- Microsoft Entra ID integration
- production identity federation

These will be introduced at the appropriate architecture boundaries.

## Relationship to Slurm Accounting

Phase 02 established the accounting model:

```text
Cluster
  ↓
Account
  ↓
User association
  ↓
QOS / TRES policy
  ↓
Resource allocation
```

Phase 03 does not replace that model. It automates the **compute-node side** that ultimately consumes the resources governed by that model.

The controller/accounting plane and worker plane remain intentionally distinct.

## Future Enterprise Identity Integration

A production organization may use Microsoft Entra ID or another enterprise identity provider for authentication and group membership.

That identity system should not be confused with Slurm's accounting objects.

Conceptually:

```text
Microsoft Entra ID
        ↓
Enterprise identity / groups
        ↓
Linux identity and access
        ↓
Slurm user + account associations
        ↓
QOS / resource policy
        ↓
GPU allocation
```

A single user may legitimately have access to multiple Slurm accounts, and a single Slurm account may contain many users. Multiple Slurm clusters can also share a central accounting service.

This is deferred until the identity/multi-tenancy phase so that we first establish the infrastructure fundamentals.

## Phase Status

**Architecture:** IN PROGRESS

**Implementation:** NOT STARTED

**GPU worker onboarding:** NOT STARTED

**Validation:** NOT STARTED

**Failure testing:** DEFERRED until real compute nodes exist.

## Phase 03 Acceptance Criteria

Phase 03 will not be considered complete until:

- the Ansible repository structure is implemented
- a fresh GPU worker can be configured reproducibly
- roles are separated by responsibility
- secrets are excluded from Git
- the playbook is demonstrably idempotent
- GPU/NVIDIA state is validated
- MUNGE state is validated
- Slurm/GRES/cgroup state is validated
- controller registration is validated against real workers
- rebuild steps are documented
- encountered failures and fixes are recorded
- the final architecture is documented
