# Lab 01 — Operating Standards

This document is the baseline execution standard for Lab 01 and is also the quality bar to carry into the subsequent AI infrastructure labs.

## 1. Production-shaped, zero-to-hero execution

The lab is built from ground zero and should resemble an AI/HPC factory as closely as the selected Nebius resources allow. We do not optimize for the shortest command sequence; we optimize for understanding the production architecture, operating model, failure boundaries and troubleshooting workflow.

Every phase must be executable, validated and finalized before the next phase begins.

Each phase should contain:

1. Pre-flight and hardware/software baseline inspection.
2. Ground-up implementation with exact commands and complete configuration.
3. Health gates and explicit acceptance criteria.
4. Real workload execution where the phase supports workloads.
5. Continuous or targeted observability and evidence capture.
6. Deliberate failure injection.
7. Evidence-driven troubleshooting and remediation.
8. Recovery and final health validation.
9. Rebuild/automation material so the phase can be reproduced without repeating expensive manual work unnecessarily.
10. Interview checkpoint with architecture, trade-offs and production lessons.

## 2. Real workloads are mandatory

Training and inference must represent real GPU work, not toy validation.

Do not consider any of the following a sufficient workload acceptance test by itself:

- `print()` from PyTorch.
- A trivial CUDA sample.
- A one-shot `nvidia-smi` output.
- A synthetic command that does not exercise the relevant production path.

Where training is part of a phase, use a real model/dataset workload that produces sustained GPU utilization, meaningful HBM activity, storage reads, checkpoint writes and, where applicable, inter-GPU/NCCL communication. Workloads should normally run long enough to observe behavior and perform an incident drill.

Where inference is part of a phase, use a real serving model and measure request processing, tokenization, batching, latency, throughput, GPU/HBM behavior and the serving runtime path.

## 3. GPU host strategy

### First GPU node

The first GPU node is intentionally a plain Ubuntu Nebius GPU VM. We install and understand the stack manually, including as applicable:

- NVIDIA driver
- CUDA toolkit/runtime
- NVIDIA Container Toolkit
- Docker/container runtime integration
- DCGM
- RDMA/InfiniBand components where the selected hardware exposes them
- Slurm GPU integration
- Enroot/Pyxis
- GPU and system observability

This is the reference host for understanding how the stack is assembled from the operating system upward.

### Later expensive GPU nodes

Once the manual stack is understood, later high-cost GPU nodes should use an appropriate Nebius preconfigured GPU environment where it provides the required production components. Do not spend expensive GPU hours repeatedly installing software by hand.

Use Ansible to:

- discover the host
- verify hardware and topology
- verify driver/CUDA compatibility
- verify containers and GPU runtime
- verify DCGM
- verify RDMA/InfiniBand/RoCE prerequisites
- verify Slurm/Pyxis/Enroot
- detect configuration drift
- remediate where appropriate
- generate a readiness report

## 4. Expensive-resource rule

Before starting an expensive multi-GPU cluster, all possible low-cost preparation must already be complete.

Preflight must cover:

- Nebius VPC/networking
- routes
- shared storage
- DNS/host naming where required
- IAM/service accounts
- Ansible
- configuration templates
- Slurm controller configuration
- user/account/QOS definitions where applicable
- container images and model preparation
- training scripts
- checkpoint strategy
- monitoring collectors
- failure-drill commands
- incident collection scripts
- rebuild/destroy scripts

The goal is to provision the expensive GPU resources, attach them to the prepared control plane, validate them, launch the workload and immediately begin the planned experiment.

## 5. Continuous evidence collection

Every real GPU experiment should have background telemetry collection where practical.

Capture at minimum the relevant subset of:

### GPU

- `nvidia-smi`
- `nvidia-smi -q`
- `nvidia-smi dmon`
- GPU topology
- NVLink state/counters where available
- utilization, memory/HBM, clocks, power, temperature, ECC and XID information

### DCGM

Capture GPU utilization, memory/HBM behavior, clocks, temperature, power, PCIe/NVLink metrics and error/throttling indicators available from the installed DCGM version.

### CPU/NUMA

- `lscpu`
- NUMA topology
- CPU/memory utilization
- `/proc/meminfo`
- `vmstat`
- `mpstat`
- PSI: `/proc/pressure/cpu`, `/proc/pressure/memory`, `/proc/pressure/io`

### PCIe

- `lspci`
- `lspci -tv`
- relevant `lspci -vv` output

### RDMA/InfiniBand

Where present:

- `ibstat`
- `ibdev2netdev`
- `ibv_devinfo`
- `rdma link`
- `rdma dev`
- NIC/RDMA counters

### Network

- `ip -s link`
- `ss -s`
- `ethtool`
- interface statistics

### Storage

- `iostat`
- filesystem/mount information
- throughput/latency evidence
- I/O pressure
- relevant filesystem-specific statistics

### NCCL

For distributed workloads capture relevant NCCL debug output, including topology, transport, interface selection, errors and timing.

### Slurm

Capture relevant:

- `sinfo`
- `squeue`
- `scontrol`
- controller logs
- `slurmd` logs
- job output/error logs

## 6. Monitoring modes

Two collection modes are required.

### Continuous collector

A lightweight background collector runs during GPU experiments and writes timestamped evidence into a structured directory, for example:

```text
evidence/<date>/<node>/
  gpu/
  dcgm/
  nvlink/
  pcie/
  numa/
  rdma/
  network/
  storage/
  kernel/
  slurm/
```

### Incident snapshot

A dedicated evidence script must capture a complete point-in-time diagnostic package when an incident is injected or observed.

Example interface:

```bash
./collect-evidence.sh --incident nccl-timeout
```

The exact script and implementation are created during the applicable phase.

## 7. Failure-driven learning

Failure drills are first-class lab work.

For each planned incident:

1. Establish a healthy baseline.
2. Start a workload when required.
3. Inject the failure deliberately and safely.
4. Observe the symptom without immediately looking at the fix.
5. Build an evidence chain across Slurm, kernel, GPU, network, RDMA, storage and workload logs.
6. Identify the failure boundary/root cause.
7. Remediate.
8. Verify recovery.
9. Compare before/during/after evidence.
10. Record the production lesson.

Examples include:

- GRES mismatch
- node registration failure
- job pending/resource bottleneck
- drained node
- Slurm daemon failure
- storage stall
- RDMA path failure
- NCCL timeout
- GPU error/XID where safe to reproduce or simulate
- container GPU runtime failure

Failure injection must never intentionally damage the Nebius control plane or create uncontrolled external impact.

## 8. Rebuild and automation strategy

Use two execution paths throughout the lab:

### Manual path

Build and tune the system interactively. This is the learning path and the source of truth for understanding what each component does.

### Automated path

At the end of every phase, capture the verified implementation as reusable automation. Prefer:

- Ansible roles/playbooks for host configuration.
- Shell scripts for evidence collection and deterministic local operations.
- Nebius infrastructure automation where appropriate.
- One common GitHub Actions workflow per lab with manual phase selection rather than creating a separate workflow for every phase.

For expensive compute, the preferred daily workflow is:

```text
Prepare low-cost infrastructure
        ->
Provision expensive GPU compute
        ->
Attach/onboard with Ansible
        ->
Run readiness gate
        ->
Run workload/experiment
        ->
Collect evidence
        ->
Run failure drill
        ->
Recover and validate
        ->
Destroy expensive compute
```

Persistent low-cost resources such as suitable storage/network foundations may remain when economically sensible.

Snapshots/images should be used when they genuinely reduce rebuild time and preserve a verified state; they should not replace understanding the ground-up installation phase.

## 9. Production data path must remain visible

For distributed training, we should be able to explain and observe the complete path:

```text
Model / Dataset
      |
      v
Shared / Remote Storage
      |
      v
CPU / NUMA / PCIe
      |
      v
GPU HBM <----> GPU compute
      |
      +---- NVLink/NVSwitch where available
      |
      +---- ConnectX / RDMA / InfiniBand or RoCE
                    |
                    v
                Remote GPU
```

The objective is to correlate application behavior with infrastructure telemetry rather than treating NCCL, GPU memory, networking and storage as isolated topics.

## 10. Quality gate

A phase is not complete because the commands succeeded once.

A phase is complete only when:

- the intended architecture is deployed;
- the health gate passes;
- the real workload path is demonstrated where applicable;
- relevant telemetry is captured;
- at least the planned failure drills have been executed;
- recovery has been demonstrated;
- the implementation is documented with the exact commands/configuration that actually worked;
- failures encountered during the live build are incorporated into the documentation;
- the verified automation/rebuild path is available;
- the interview-level architectural lessons are recorded.

## 11. Living-document rule

The repository is the evolving source of truth.

If a command fails during live execution, a configuration needs to change, a Nebius resource behaves differently from the documentation, or a troubleshooting procedure reveals a missing step:

1. Fix the implementation.
2. Verify the fix.
3. Update the phase documentation.
4. Update automation.
5. Record the failure and resolution where useful.

Do not silently overwrite the history of what was learned.
