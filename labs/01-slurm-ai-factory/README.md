# Lab 01 — Slurm AI Factory

Production-shaped HPC/AI Factory environment built from the ground up on Nebius.

## Phase progression

- phase-00 — Infrastructure contract and prerequisites
- phase-01 — Nebius infrastructure foundation
- phase-02 — Slurm control plane
- phase-03 — GPU discovery, GRES and isolation
- phase-04 — Accounting, tenants, QOS and policy
- phase-05 — Pyxis and Enroot
- phase-06 — Real single-GPU training
- phase-07 — Training observability
- phase-08 — Checkpointing and recovery
- phase-09 — NCCL single-node baseline
- phase-10 — Multi-node GPU networking and RDMA
- phase-11 — Real distributed training
- phase-12 — NCCL/network failure drills
- phase-13 — Slurm production incident drills
- phase-14 — Capacity and maintenance operations
- phase-15 — Boundary to subsequent labs
- phase-16 — Final AI Factory acceptance gate

## Execution standard

The lab follows [`LAB-OPERATING-STANDARDS.md`](./LAB-OPERATING-STANDARDS.md). Every phase is a production-shaped, zero-to-hero implementation: exact build steps, health gates, real workloads, continuous/incident evidence capture, deliberate failure injection, troubleshooting, recovery and verified rebuild automation.

Real training/inference is mandatory where applicable. Toy commands such as a standalone `nvidia-smi`, `print()` or trivial CUDA sample are diagnostic checks only and are never considered workload validation.

The first GPU host is intentionally built from a plain Ubuntu Nebius GPU VM to understand the stack from the OS upward. Later expensive GPU nodes should use suitable Nebius preconfigured GPU environments and be validated/onboarded with Ansible to minimize expensive setup time.

At the end of each phase, the verified manual implementation is converted into reusable automation. Use one common manually-triggerable GitHub Actions workflow per lab with phase selection rather than creating a separate workflow for every phase.

Each phase's documentation is a living record: commands, configuration changes, Nebius-specific behavior, failures and fixes discovered during live execution must be incorporated after verification.
