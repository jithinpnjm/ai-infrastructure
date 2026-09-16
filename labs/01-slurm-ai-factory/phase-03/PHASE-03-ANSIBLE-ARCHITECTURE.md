# Phase 03 — Ansible Architecture and Implementation

## Objective

Build a production-shaped Ansible configuration-management layer for onboarding GPU compute nodes into the AI factory.

The target convergence chain is:

```text
Fresh GPU VM
    ↓
Ansible
    ↓
OS prerequisites
    ↓
NVIDIA + CUDA validation
    ↓
MUNGE
    ↓
Slurm + GRES
    ↓
cgroup v2
    ↓
Validation
    ↓
Slurm worker ready
```

Phase 01 intentionally built one L40S worker manually so the dependency chain could be understood. Phase 03 converts that learned configuration into repeatable, idempotent configuration management.

## Architectural Boundary

```text
Nebius
  → VM / GPU / network / storage / lifecycle

Ansible
  → OS / NVIDIA / MUNGE / Slurm worker / GRES / cgroup / validation

Slurm
  → scheduling / CPU / memory / GPU allocation / accounting integration
```

Nebius provisioning is deliberately not part of this phase. Terraform and cloud API automation are deferred.

## Repository Implementation

```text
phase-03/
├── PHASE-03-ANSIBLE-ARCHITECTURE.md
├── tools/
│   └── validate-ansible.sh
└── ansible/
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

## Role Execution Order

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

### `base`

Installs common worker prerequisites, establishes the lab timezone, verifies systemd and requires the unified cgroup hierarchy.

### `nvidia`

The lab will use Nebius' preconfigured GPU image. Therefore driver installation is **opt-in**, not automatic.

The role validates the actual GPU with `nvidia-smi`, including expected GPU count and model. CUDA compiler availability can also be checked.

This avoids replacing a vendor-supplied driver merely because Ansible was executed.

### `munge`

Installs MUNGE, deploys the trusted cluster key, enforces ownership/mode, starts the service and validates `munge -n | unmunge`.

The MUNGE key is never committed to Git.

### `slurm`

Installs the worker packages and generates:

- `/etc/slurm/slurm.conf`
- `/etc/slurm/gres.conf`
- `/etc/slurm/cgroup.conf`

The worker configuration uses the lab cluster name/controller, `auth/munge`, `select/cons_tres`, `CR_CORE_MEMORY`, GPU GRES and cgroup task plugins.

`slurm.conf` is generated from the complete `gpu_workers` inventory group so worker nodes have a consistent view of the cluster. Hardware-specific CPU/memory values can be overridden after the actual VM is verified.

`gres.conf` uses NVML discovery and validates the expected L40S GPU and device file.

The cgroup configuration carries forward the Phase 01 validated controls:

```text
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
```

### `validation`

Validation is a first-class acceptance layer. It checks:

- `/dev/nvidia0`
- cgroup v2
- MUNGE service
- Slurm service
- `slurmd -G`
- optional controller reachability
- optional `nvcc`

A separate validation playbook allows the validation role to be rerun without reconverging the entire node.

## Inventory Model

The lab inventory intentionally contains **zero GPU hosts right now**.

The intended shape is:

```yaml
gpu_workers:
  hosts:
    l40-node-01:
      ansible_host: <verified-private-ip>
    l40-node-02:
      ansible_host: <verified-private-ip>
```

The addresses and hardware overrides will only be populated after Phase 04 creates the actual Nebius instances.

This keeps infrastructure discovery separate from configuration logic and avoids inventing hardware facts.

## Secret Boundary

Git contains configuration and references, never secret material.

For the current lab implementation the MUNGE key is supplied out-of-band on the Ansible controller at:

```text
phase-03/ansible/secrets/munge.key
```

`*.key` is already excluded by the repository `.gitignore`.

The repository documents this boundary without storing the key. Ansible Vault or an external secret manager can replace the controller-local mechanism later if the lab evolves into a multi-user automation service.

## Idempotency

The design target is:

```text
First run  → resources/configuration converge
Second run → ideally changed=0
```

Idempotency is not considered proven until a real worker has been converged twice and the second run is inspected.

## Offline Validation

The implementation can be checked without any GPU VM:

```bash
bash labs/01-slurm-ai-factory/phase-03/tools/validate-ansible.sh
```

The script verifies the expected repository tree and, when `ansible-playbook` is installed, runs syntax checks for both playbooks.

No GPU VM is required for this phase of implementation.

## Runtime Validation Deferred

The following cannot be truthfully marked complete without a real worker:

- actual Ansible convergence
- second-run idempotency
- controller registration
- `sinfo`/`scontrol` node state
- real Slurm GPU allocation
- cgroup GPU isolation under a job
- MUNGE cross-node authentication
- failure/recovery tests

These are runtime acceptance tests for the next compute stage, not reasons to delay completion of the Ansible code itself.

## Relationship to Phase 02

Phase 02 established:

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

Phase 03 automates the worker side that supplies those allocatable resources. It does not replace the accounting plane.

## Explicitly Deferred

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

These remain separate architecture phases.

## Status

**Architecture:** COMPLETE

**Ansible implementation:** COMPLETE for offline/static review

**Static validation tooling:** COMPLETE

**GPU worker onboarding:** DEFERRED to Phase 04

**Runtime/idempotency validation:** DEFERRED until real workers exist

**Failure/recovery testing:** DEFERRED until real workers and workloads exist

## Acceptance Boundary

Phase 03 is considered complete as a code/architecture phase when:

- repository structure exists
- roles are separated by responsibility
- secrets are excluded from Git
- playbooks and templates are implemented
- offline validation is available
- rebuild/convergence flow is documented
- runtime tests are explicitly identified as deferred rather than falsely marked successful

The next phase can therefore provision the two L40S workers and exercise this automation against real infrastructure.
