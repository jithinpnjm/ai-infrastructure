# Lab 01 — Phase 01: Controller Baseline

## Status

Slurm controller + L40S compute-node foundation is operational. GRES allocation and cgroup v2 resource isolation have been validated. Detailed configuration, tests, meanings, and cgroup hierarchy are recorded in `SLURM-FOUNDATION-NOTES.md`.

## Host

- Hostname: `slurm-controller-01`
- Nebius instance: `computeinstance-e00vapssm4vybk21r6`
- OS: Ubuntu 24.04.4 LTS
- Kernel: `6.11.0-1016-nvidia`
- Architecture: x86_64
- CPU: 4 vCPU, Intel Xeon Gold 6338
- Memory: 15 GiB
- Root disk: 200 GB
- Private IP observed: `10.0.0.4`

## Slurm

- Slurm version: `23.11.4`
- Cluster name: `ai-factory-lab` — LOCKED; do not change casually after state initialization.
- Controller service: active
- `scontrol ping`: `Slurmctld(primary) at slurm-controller-01 is UP`
- Partition: `gpu`
- Compute node: `l40-node-01`
- `SelectType=select/cons_tres`
- `SelectTypeParameters=CR_CORE_MEMORY`
- `GresTypes=gpu`
- `Gres=gpu:L40S:1`

## Authentication

- MUNGE service: active/running
- Slurm authentication: `auth/munge`
- `munge -n | unmunge`: `STATUS: Success (0)`

## Cgroup v2 / resource enforcement

- `TaskPlugin=task/cgroup` configured on controller and compute node.
- Compute node uses cgroup v2 at `/sys/fs/cgroup`.
- `CgroupPlugin=autodetect`.
- Relevant `cgroup.conf` settings:
  - `CgroupMountpoint=/sys/fs/cgroup`
  - `ConstrainCores=yes`
  - `ConstrainDevices=yes`
  - `ConstrainRAMSpace=yes`
  - `ConstrainSwapSpace=yes`
  - `AllowedSwapSpace=200`
- CPU allocation test: `--cpus-per-task=4` resulted in `cpuset.cpus.effective=0-3`.
- Memory allocation test: `--mem=4096M` resulted in `memory.max=4294967296` at the step/user cgroup level.
- GPU allocation test: `--gres=gpu:L40S:1` resulted in `CUDA_VISIBLE_DEVICES=0` and visible L40S.
- No-GPU test: job without `--gres` resulted in `CUDA_VISIBLE_DEVICES=` and `nvidia-smi -L` reported `No devices found.`
- Actual cgroup path observed:
  `/system.slice/l40-node-01_slurmstepd.scope/job_<id>/step_0/user/task_0`

## Issues/lessons captured

### Cluster name mismatch

The controller state was initially initialized with `ClusterName=ai-infra-lab`. The configuration was later changed to `ai-factory-lab`, causing Slurm's persistent-state safety check to report `CLUSTER NAME MISMATCH`. The new cluster identity was intentionally accepted during this lab startup. The cluster name is now fixed as `ai-factory-lab`.

### GRES naming mismatch

The NVIDIA GPU is exposed to Slurm as `gpu:L40S`. A hierarchical name such as `NVIDIA:GPU:L40S` is not the correct syntax for this GRES configuration. `slurmd -G` confirmed `Type=L40S` and `/dev/nvidia0` mapping.

### Cgroup example-version mismatch

The package example `cgroup.conf` contained deprecated/unrecognized options `CgroupAutomount` and `ConstrainKmemSpace`. Slurm 23.11.4 rejected them. They were removed; the remaining cgroup v2 configuration initialized successfully.

### AccountingStorageTRES / GPU TRES lesson

Adding `gres/gpu` to `AccountingStorageTRES` was attempted to make GPU TRES visible in `CfgTRES`. Slurm then refused to start because this GPU TRES accounting configuration requires `slurmdbd`. The line was removed. GPU scheduling through GRES works without `slurmdbd` in this phase.

### Memory cgroup hierarchy lesson

The task leaf cgroup initially showed `memory.max=max`, which could look like missing enforcement. Inspection of its parent `step_0/user` cgroup showed `memory.max=4294967296` for a 4096 MiB allocation. Limits can therefore be applied at a parent level in the Slurm/systemd hierarchy rather than being duplicated on every leaf task cgroup.

### PMIx warning

Slurm 23.11.4 reports that `mpi/pmix` and `mpi/pmix_v5` cannot load the PMIx library because PMIx is not installed. This is not blocking the current single-node controller/GPU foundation and will be addressed when MPI/PMIx workloads are introduced.

### Configuration validation command

This Slurm build does not support the commonly assumed `slurmctld -t` validation option. Use the installed Slurm version's supported options and service/configuration validation methods rather than assuming flags from another version.

## Detailed record

See `SLURM-FOUNDATION-NOTES.md` for the step-by-step explanation of the configuration, validation evidence, resource flow, and the meaning of Slurm job/step/user/task cgroup levels.
