# Phase 00 Acceptance Criteria

Phase 00 is an architecture/readiness gate. No production-sized GPU cluster should be left running merely because Phase 00 exists.

## Infrastructure

- [ ] Nebius project and region confirmed.
- [ ] GPU-cluster SKU and region confirmed.
- [ ] H100/InfiniBand quota/capacity checked.
- [ ] L40S daily-use option confirmed.
- [ ] Controller VM target confirmed.
- [ ] VPC/subnet/security-group model confirmed.
- [ ] Shared filesystem target confirmed.
- [ ] Object Storage target confirmed.

## Network

- [ ] Management/data-plane distinction documented.
- [ ] GPU-to-NIC topology experiment defined.
- [ ] InfiniBand/RDMA validation commands identified.
- [ ] NCCL network validation path defined.

## Storage

- [ ] Models path defined.
- [ ] Dataset path defined.
- [ ] Checkpoint path defined.
- [ ] Object Storage artifact path defined.
- [ ] Local-cache/storage comparison experiment defined.

## Software

- [ ] OS baseline selected.
- [ ] NVIDIA driver strategy defined.
- [ ] CUDA strategy defined.
- [ ] Container Toolkit strategy defined.
- [ ] Slurm version strategy defined.
- [ ] Munge strategy defined.
- [ ] GRES/cgroup strategy defined.
- [ ] Pyxis/Enroot strategy defined.
- [ ] Accounting database strategy defined.
- [ ] Monitoring/DCGM strategy defined.

## Workloads

- [ ] Real single-GPU training workload selected.
- [ ] Real checkpointing workload selected.
- [ ] NCCL benchmark plan defined.
- [ ] Real multi-node training workload selected.
- [ ] Failure/recovery workload defined.

## Operations

- [ ] Persistent/ephemeral resource matrix defined.
- [ ] Daily create/use/destroy lifecycle defined.
- [ ] Terraform boundary defined.
- [ ] Ansible boundary defined.
- [ ] Single GitHub Actions workflow-per-lab design defined.
- [ ] Secrets/environment boundary defined.

## Evidence

- [ ] Architecture committed to Git.
- [ ] Nebius documentation references recorded.
- [ ] Pricing/cost assumptions recorded with date.
- [ ] Actual project quota/capacity results will be recorded in `RESULTS.md` during execution.
