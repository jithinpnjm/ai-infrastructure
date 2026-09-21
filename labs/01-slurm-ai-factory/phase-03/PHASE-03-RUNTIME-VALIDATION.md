# Phase 03 — Runtime Validation Addendum

## Status correction

The original Phase 03 architecture document was written before real GPU workers existed, so its status section correctly marked runtime validation as deferred at that time.

That runtime boundary has now been crossed in Phase 04.

The Phase 03 Ansible implementation was exercised against two real Nebius L40S workers and successfully converged the worker-side configuration.

For the current status and complete evidence, use:

```text
phase-04/PHASE-04-RUNTIME-VALIDATION-AND-INCIDENTS.md
phase-04/CONTROLLER-SNAPSHOT-RECOVERY.md
```

## Runtime capabilities validated

- Ansible SSH connectivity to both workers.
- Base worker convergence.
- Deterministic worker hostnames.
- NVIDIA L40S and driver validation.
- MUNGE installation/configuration.
- Slurm worker installation/configuration.
- GRES configuration and `slurmd -G` validation.
- cgroup v2 prerequisite.
- Slurm controller/worker registration.
- GPU partition availability.
- `srun --gres=gpu:1` allocation.
- NVIDIA GPU visibility inside a Slurm allocation.
- Slurm accounting of a completed GPU job.
- CUDA 13.0 runtime visibility.
- CUDA 13.0 toolkit / `nvcc 13.0.88`.
- Real CUDA kernel execution through Slurm.

## Runtime issues that became part of the design

The runtime exercise also exposed important automation requirements:

1. Cloud-generated hostnames must not become the cluster's logical node names.
2. Worker `slurm.conf` must follow the current controller network identity.
3. Controller node definitions must match actual worker hardware.
4. Hardware values should be obtained from `slurmd -C`, not guessed from an instance specification or stale VM.
5. Validation must capture both stdout and stderr where diagnostic commands use either stream.
6. MUNGE failures require authentication-layer investigation rather than assumptions about GPU or Slurm scheduling.
7. VM unresponsiveness must be separated from Slurm daemon failures.
8. Controller snapshot recovery requires network-identity verification.
9. GPU infrastructure validation should not depend on an ML framework being preinstalled.
10. A real CUDA kernel is a stronger GPU execution acceptance test than `nvidia-smi` alone.

## Idempotency note

Ansible was rerun successfully after the controller IP changed, and the worker configuration converged without rebuilding the nodes.

The lab should continue to capture explicit second-run `changed=0` evidence on a future fresh worker pair before treating idempotency as a formal acceptance criterion.

## Architectural boundary

The Ansible layer currently owns:

```text
worker OS
NVIDIA validation
MUNGE
Slurm worker
GRES
cgroup
worker validation
```

It does not yet own:

```text
Nebius VM creation
controller provisioning
controller configuration lifecycle
controller IP allocation
GPU software/container application environments
NCCL / InfiniBand
Kubernetes GPU scheduling
```

Those remain later automation/architecture boundaries.
