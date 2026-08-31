# AI Infrastructure

Production-shaped AI Factory learning and hands-on implementation repository.

## Lab principles

- Build manually first to understand the system.
- Use real training and inference workloads, not toy GPU tests.
- Measure the complete path: compute, HBM, NUMA, PCIe, storage, networking, NCCL and scheduler behavior.
- Deliberately inject failures and troubleshoot from evidence.
- Convert every working phase into reproducible Terraform/Ansible/GitHub Actions automation.
- Keep the repository as a living record of commands, fixes, deviations, baselines and operational lessons.

## Labs

- `labs/01-slurm-ai-factory` — Slurm/HPC AI Factory
- `labs/02-kubernetes-ai-factory` — Bare-metal Kubernetes, NVIDIA GPU Operator and DRA
- `labs/03-runai` — AI workload orchestration on Kubernetes
- `labs/04-networking` — PCIe, SR-IOV, RDMA, InfiniBand, RoCE, GPUDirect and NCCL
- `labs/05-distributed-training` — Production-shaped multi-GPU/multi-node training
- `labs/06-inference` — Triton, vLLM and NIM serving
- `labs/07-operations` — Ansible, BCM concepts, fleet lifecycle, upgrades and incident operations

## Reproducibility

Expensive GPU infrastructure should be disposable and reproducible. Each phase will provide appropriate Terraform, Ansible, validation and manually-triggered GitHub Actions workflows. Persistent storage and model/data artifacts are kept independently where practical.

## Living knowledge

When an actual execution differs from the documented procedure, update the runbook and automation with the observed failure, evidence, root cause, remediation and validation. Do not silently erase operational history.
