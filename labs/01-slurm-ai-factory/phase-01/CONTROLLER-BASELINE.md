# Lab 01 — Phase 01: Controller Baseline

## Status

Controller foundation is operational. GPU-node work is intentionally deferred to the next session.

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
- Planned compute node: `l40-node-01`

## Authentication

- MUNGE service: active/running
- Slurm authentication: `auth/munge`

## Resource management

- `SelectType=select/cons_tres`
- `SelectTypeParameters=CR_CORE`
- Slurm cgroup enforcement has **not** yet been configured. Kernel cgroup controllers are present, but `/proc/cgroups` alone does not prove Slurm cgroup enforcement. Cgroup configuration will be handled on the compute-node/Slurm worker stage when resource isolation is studied.

## Issues/lessons captured

### Cluster name mismatch

The controller state was initially initialized with `ClusterName=ai-infra-lab`. The configuration was later changed to `ai-factory-lab`, causing Slurm's persistent-state safety check to report `CLUSTER NAME MISMATCH`. The new cluster identity was intentionally accepted during this lab startup. The cluster name is now fixed as `ai-factory-lab`.

### PMIx warning

Slurm 23.11.4 reports that `mpi/pmix` and `mpi/pmix_v5` cannot load the PMIx library because PMIx is not installed. This is not blocking the controller foundation and will be addressed when MPI/PMIx workloads are actually introduced.

### Node DNS

The controller currently cannot resolve `l40-node-01`; this is expected because the actual compute node has not yet been created/configured.

### Configuration validation command

This Slurm build does not support the commonly assumed `slurmctld -t` validation option. Use the installed Slurm version's supported options and service/configuration validation methods rather than assuming flags from another version.

## Next execution

Create the disposable `l40-node-01` L40S VM and perform the bare-Ubuntu GPU software installation manually. Do not start Ansible or the preconfigured Nebius GPU image workflow yet.
