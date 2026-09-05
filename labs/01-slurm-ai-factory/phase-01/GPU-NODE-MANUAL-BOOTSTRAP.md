# Lab 01 — Phase 01: Manual NVIDIA GPU Node Bootstrap

## Purpose

This document records the **manual GPU-node bootstrap performed before the cluster was moved toward Ansible-based configuration**.

The node documented here was an exploratory/reference node. Its purpose was to understand the NVIDIA GPU software and hardware stack, establish the relationship between Linux GPU devices and Slurm GRES, and prove the basic Slurm compute-node path manually.

> **Phase boundary:** this node was deliberately temporary. It has been deleted. The next compute nodes will be created fresh and configured through Ansible.

Future phases will extend this foundation with:

- Ansible implementation and repeatable provisioning
- multi-node configuration
- MPI/PMIx/NCCL
- InfiniBand and GPUDirect RDMA
- distributed training
- observability
- failure injection and recovery
- security hardening
- performance tuning
- node lifecycle and rebuild automation
- architecture redesigns

Where something remains uncertain or was intentionally deferred, it is recorded rather than silently filled in.

---

## Phase 01 outcome

| Area | Result |
|---|---|
| GPU platform | Nebius `gpu-l40s-d` |
| GPU | NVIDIA L40S |
| GPU count | 1 |
| CPU | AMD EPYC Genoa, 16 vCPU |
| Memory | ~96 GiB |
| OS | Ubuntu 24.04.4 |
| NVIDIA driver | 580.173.02 |
| CUDA Toolkit | 13.0 / `nvcc 13.0.88` |
| Slurm | 23.11.4 |
| Cluster | `ai-factory-lab` |
| MUNGE | Validated |
| GRES | `gpu:L40S` validated |
| cgroup | cgroup v2 CPU/memory/device enforcement validated |
| Real CUDA workload | Validated |
| Final node state | **Deleted after documentation** |

---

# 1. Role of the manual node

The first L40S compute node was deliberately configured manually.

The learning sequence was:

```text
Nebius GPU VM
    │
    ▼
Linux / PCIe
    │
    ▼
NVIDIA driver
    │
    ▼
NVIDIA kernel module + device nodes
    │
    ▼
CUDA Toolkit / CUDA runtime
    │
    ▼
Real CUDA workload
    │
    ▼
GPU telemetry / topology
    │
    ▼
MUNGE
    │
    ▼
Slurm slurmd
    │
    ▼
GRES discovery
    │
    ▼
cgroup v2 enforcement
    │
    ▼
Slurm GPU allocation
```

The node was **not intended to become the permanent production cluster node**. It was a reference implementation used to understand what later automation must reproduce.

---

# 2. Nebius GPU VM baseline

## 2.1 Platform

The compute node was created on Nebius using an L40S GPU platform.

| Property | Observed value |
|---|---|
| GPU platform | `gpu-l40s-d` |
| GPU | NVIDIA L40S |
| GPU count | 1 |
| CPU | AMD EPYC Genoa |
| vCPU | 16 |
| Memory | ~96 GiB |
| Root disk | 200 GB SSD |
| OS | Ubuntu 24.04.4 |
| Kernel | `6.11.0-1016-nvidia` |
| Private IP | `10.0.0.18` |
| Hostname | `l40-node-01` |

The VM intentionally used a **driverless image** for this manual bootstrap so the NVIDIA driver installation and resulting software stack could be studied directly.

The later Ansible phase will use the Nebius preconfigured GPU image for the new nodes. This is a deliberate change in methodology.

---

# 3. Initial hardware discovery

Before installing the NVIDIA software stack, inspect the host as a normal Linux system.

```bash
uname -a
cat /etc/os-release
lscpu
free -h
lsblk
lspci -nn
lspci -nn | grep -i -E 'nvidia|3d|vga'
```

The important progression is:

```text
PCIe device exists
      ↓
Linux kernel recognizes device
      ↓
NVIDIA kernel driver binds
      ↓
/dev/nvidia* devices appear
      ↓
nvidia-smi communicates with GPU
      ↓
CUDA executes work on GPU
```

A GPU visible in `lspci` does **not** prove that the complete NVIDIA/CUDA stack is operational.

---

# 4. NVIDIA driver bootstrap

## 4.1 Driver installation

The node initially did not have a working NVIDIA driver stack.

The Ubuntu package resolution selected:

```text
nvidia-driver-570-server
```

The installed DKMS driver was:

```text
nvidia-srv/580.173.02
```

The effective driver reported by `nvidia-smi` was:

```text
Driver Version: 580.173.02
CUDA Version:   13.0
```

### Versioning note

Package name, DKMS module version, and the version reported by `nvidia-smi` are separate pieces of evidence. During troubleshooting, check all three rather than assuming they are identical.

## 4.2 Validation

```bash
nvidia-smi
nvidia-smi -L
lsmod | grep nvidia
ls -l /dev/nvidia*
```

The successful state showed the L40S through `nvidia-smi` and exposed the NVIDIA device nodes.

### Study point: troubleshooting chain

```text
lspci
  → device detection

lsmod
  → NVIDIA kernel modules

/dev/nvidia*
  → device interface

nvidia-smi
  → NVIDIA management stack

CUDA test
  → actual compute/runtime functionality
```

Do not use `nvidia-smi` alone as proof that the complete CUDA compute environment is healthy.

---

# 5. CUDA Toolkit installation

CUDA Toolkit 13.0 was installed manually.

Validation:

```bash
nvcc --version
```

Observed compiler version:

```text
Cuda compilation tools, release 13.0, V13.0.88
```

The CUDA environment was made available through:

```text
/etc/profile.d/cuda.sh
```

### Driver vs Toolkit vs application

```text
NVIDIA driver
      ≠
CUDA Toolkit
      ≠
CUDA application/runtime
```

A host can have a working NVIDIA driver while `nvcc` is unavailable. The driver, toolkit, runtime libraries, and applications therefore need separate validation.

---

# 6. Real CUDA validation

A CUDA device-query test verified the actual GPU from the CUDA stack rather than merely checking `nvidia-smi`.

Observed result:

```text
GPU count:          1
GPU:                NVIDIA L40S
Compute Capability: 8.9
Memory:             ~44.39 GiB
```

A real CUDA vector-add operation was then executed.

Result:

```text
3.0
```

This proved an actual CUDA kernel execution path rather than device enumeration alone.

## Validation hierarchy

```text
nvidia-smi
    │
    │ management visibility
    ▼
CUDA device query
    │
    │ runtime/device visibility
    ▼
CUDA vector addition
    │
    │ actual kernel execution
    ▼
GPU workload
```

This validation pattern should be retained for future GPU-node health checks.

---

# 7. GPU stress and telemetry baseline

A real GPU stress workload was executed to establish a utilization baseline.

Observed values included approximately:

| Metric | Observation |
|---|---:|
| SM utilization | 100% |
| Memory utilization | 100% |
| Power | ~230–231 W |
| Temperature | ~56–57 °C |
| VRAM used | ~3.5 GiB |
| GPU clock | ~2520 MHz |
| Memory clock | ~9001 MHz |

These are **observations from the lab VM**, not universal L40S specifications.

Useful commands:

```bash
nvidia-smi
nvidia-smi dmon
nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,utilization.memory,memory.used,memory.total,clocks.sm,clocks.mem --format=csv
```

### Study point

Do not stop at “GPU is visible.” Drive the GPU and verify that hardware telemetry, power, clocks, temperature, and memory behavior are sane.

Future phases should turn these observations into automated health checks and monitoring.

---

# 8. PCIe baseline

The L40S is a PCIe GPU and does not use NVLink in this configuration.

The PCIe capability and negotiated link were inspected with:

```bash
lspci -vv
```

Observed:

```text
LnkCap: 16GT/s x16
LnkSta: 2.5GT/s x16
```

Therefore, in the guest environment, the device capability was higher than the observed negotiated link state. We recorded this as an environment observation and did **not** attempt to force or repair the negotiated generation.

### Study point

Always distinguish:

```text
LnkCap = capability
LnkSta = current negotiated state
```

This matters for:

- CPU-to-GPU transfers
- data loading
- GPUDirect paths
- multi-GPU communication
- NCCL performance

The PCIe baseline should be rechecked when performance benchmarking is introduced.

---

# 9. NVIDIA topology

Topology was inspected with:

```bash
nvidia-smi topo -m
```

Observed characteristics:

```text
GPU0 CPU Affinity: 0-15
NUMA:              0
NVLink:            none
```

The L40S therefore represents a different topology class from the later H100/H200 HGX systems.

## GPU classes used by the lab

| GPU class | Primary learning objective |
|---|---|
| L40S | PCIe GPU, Slurm/GRES, cgroups, PCIe-oriented workloads |
| H100/H200 HGX | 8-GPU NVLink/SXM, InfiniBand, NCCL, collective-performance studies |

Do not infer NVLink behavior from the L40S node. That belongs to the later HGX/NCCL phase.

---

# 10. MUNGE bootstrap

Slurm uses MUNGE authentication in this lab.

The controller and compute node must share the same MUNGE trust domain. The critical shared key is:

```text
/etc/munge/munge.key
```

The key was installed on the compute node with:

```text
owner: munge:munge
mode:  0400
```

The SHA-256 hash matched between controller and compute node:

```text
75dcd8df132f7be0f069906b2f504967f8eca65e834e953f7039011188d2748e
```

Validation:

```bash
systemctl is-active munge
munge -n | unmunge
```

Successful output included:

```text
STATUS: Success (0)
```

### Study point

MUNGE is not a GPU mechanism and does not perform scheduling. It belongs to the **authentication/trust layer** required for Slurm daemon communication.

```text
slurmctld
    │
    │ authenticated Slurm RPC
    ▼
slurmd
    │
    ▼
MUNGE trust
```

Later phases should cover key distribution and secret-management automation.

---

# 11. Slurm compute-node bootstrap

After the underlying GPU stack was proven, the node was integrated with Slurm.

| Property | Value |
|---|---|
| Slurm version | `23.11.4` |
| Cluster | `ai-factory-lab` |
| Node | `l40-node-01` |
| Partition | `gpu` |
| Logical GPU resource | `gpu:L40S` |
| Node-local GRES | `Name=gpu Type=L40S File=/dev/nvidia0` |

The final controller-side node definition was:

```text
NodeName=l40-node-01 NodeAddr=10.0.0.18 NodeHostname=l40-node-01 CPUs=16 Boards=1 SocketsPerBoard=1 CoresPerSocket=8 ThreadsPerCore=2 RealMemory=96556 Gres=gpu:L40S State=UNKNOWN
```

---

# 12. Physical GPU → Slurm GRES mapping

This is one of the most important concepts established during the manual build.

```text
Physical GPU
NVIDIA L40S
      │
      ▼
Linux device
/dev/nvidia0
      │
      ▼
Slurm gres.conf
Name=gpu Type=L40S File=/dev/nvidia0
      │
      ▼
Slurm controller
Gres=gpu:L40S
      │
      ▼
Job request
--gres=gpu:L40S:1
```

### Important naming lesson

The GRES type is:

```text
L40S
```

not:

```text
NVIDIA:GPU:L40S
```

An earlier configuration attempt used an incorrect hierarchical interpretation. The final configuration uses the consistent Slurm resource identity:

```text
gpu:L40S
```

This naming relationship must remain consistent across the controller configuration, `gres.conf`, and job requests.

---

# 13. GRES discovery

The compute node was checked with:

```bash
slurmd -G
```

Final discovery included:

```text
Gres Name=gpu Type=L40S Count=1 Index=0 ID=7696487 File=/dev/nvidia0
```

The important fields are:

| Field | Value |
|---|---|
| Name | `gpu` |
| Type | `L40S` |
| Count | `1` |
| Index | `0` |
| File | `/dev/nvidia0` |

This is a boundary test:

```text
NVIDIA stack works
      ↓
Linux device exists
      ↓
Slurm GRES configuration parses
      ↓
slurmd discovers GPU
```

If `slurmd -G` does not report the expected GPU, investigate that failure before debugging scheduler allocation.

---

# 14. cgroup v2 foundation

The compute node used Linux cgroup v2 through:

```text
/sys/fs/cgroup
```

Relevant Slurm configuration:

```ini
TaskPlugin=task/cgroup
CgroupMountpoint=/sys/fs/cgroup
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedSwapSpace=200
```

Conceptually:

```text
Slurm scheduler
     │
     │ allocation decision
     ▼
slurmd / slurmstepd
     │
     │ create/manage cgroups
     ▼
Linux cgroup v2
     │
     ├── CPU restriction
     ├── memory restriction
     ├── device/GPU restriction
     └── process containment / cleanup
```

### Important principle

> **Slurm decides what resources a job receives; Linux cgroups enforce those decisions on the compute node.**

---

# 15. cgroup v2 configuration compatibility issue

The example configuration shipped with the installed Slurm package contained options that were not accepted by the installed Slurm version.

Problematic options included:

```text
CgroupAutomount
ConstrainKmemSpace
```

`slurmd` initially failed while parsing the configuration. Removing the obsolete options allowed the node to recover.

### Operational lesson

Do not assume that a configuration example from documentation, package files, or an older deployment is valid for the exact installed Slurm version.

Use this workflow:

```text
Installed version
      ↓
Version-specific documentation
      ↓
Configuration
      ↓
Parser / service validation
      ↓
Runtime validation
```

This becomes especially important when the configuration is converted into Ansible templates.

---

# 16. CPU enforcement validation

A job was launched with:

```bash
srun -p gpu --gres=gpu:L40S:1 --cpus-per-task=4 --mem=4096M --pty bash
```

Inside the job cgroup, the effective CPU set was checked:

```bash
cat /sys/fs/cgroup$CG/cpuset.cpus.effective
```

Observed result:

```text
0-3
```

### What this proves

Slurm's CPU allocation was translated into a Linux cpuset restriction.

This is stronger than merely observing that the process was launched by `srun`.

---

# 17. Memory enforcement validation

The same resource-constrained job was used to validate the memory path.

Requested memory:

```text
4096M
```

The effective cgroup limit observed in the job hierarchy was:

```text
memory.max = 4294967296
```

### What this proves

The scheduler's memory request was translated into a kernel-enforced cgroup memory limit.

An important troubleshooting observation from the lab was that the effective limit could appear at a **parent cgroup** rather than only at the most obvious leaf path.

When validating cgroup behavior, inspect the complete job/step/user/task hierarchy rather than assuming the limit will exist at one exact directory.

---

# 18. GPU device enforcement validation

The node was tested both with and without a GPU allocation.

## GPU allocation

```bash
srun -p gpu --gres=gpu:L40S:1 --pty bash
```

Inside the allocation:

```text
CUDA_VISIBLE_DEVICES=0
```

and the L40S was visible through:

```bash
nvidia-smi -L
```

## No-GPU allocation

A job without a GPU allocation was tested.

Observed state:

```text
CUDA_VISIBLE_DEVICES=
```

and:

```text
nvidia-smi -L
No devices found.
```

### What this proves

`ConstrainDevices=yes` was not merely configured; it produced an observable device-isolation result.

```text
Slurm GPU allocation
        ↓
slurmstepd
        ↓
cgroup device policy
        ↓
GPU visible only to allocated job
```

This is a key production concept: **resource accounting and resource isolation are separate concerns, and the latter needs kernel enforcement.**

---

# 19. Observed Slurm cgroup hierarchy

During the validation, a representative cgroup path was observed as:

```text
/system.slice/l40-node-01_slurmstepd.scope/job_<id>/step_0/user/task_0
```

The exact job identifiers are intentionally represented symbolically here.

### Study point

When troubleshooting Slurm resource enforcement, correlate:

```text
job ID
  ↓
step ID
  ↓
slurmstepd scope
  ↓
cgroup path
  ↓
CPU / memory / device controls
```

This provides a useful bridge between the Slurm control plane and the Linux kernel enforcement layer.

---

# 20. End-to-end Slurm GPU allocation

The final end-to-end allocation test was:

```bash
srun -p gpu --gres=gpu:L40S:1 --pty bash
```

Inside the allocation:

```text
hostname=l40-node-01
CUDA_VISIBLE_DEVICES=0
```

and:

```bash
nvidia-smi -L
```

reported the L40S GPU UUID.

The controller reported the node as available in the `gpu` partition before the node was deleted.

The final scheduling path was therefore proven:

```text
User job request
      ↓
Slurm controller
      ↓
Partition / node selection
      ↓
GRES allocation
      ↓
slurmd / slurmstepd
      ↓
cgroup enforcement
      ↓
/dev/nvidia0
      ↓
CUDA_VISIBLE_DEVICES
      ↓
NVIDIA GPU
```

---

# 21. Configuration issues encountered and resolved

## 21.1 Cluster-name mismatch

The cluster name was changed during the build from an earlier value to:

```text
ai-factory-lab
```

Existing Slurm state still contained the previous cluster identity, causing a **cluster name mismatch**.

Recovery required removing the stale cluster-name state and restarting `slurmctld` with the intended configuration.

### Lesson

Once Slurm state exists, treat `ClusterName` as a deliberate identity attribute. Do not casually change it during normal operations.

---

## 21.2 Incorrect GRES naming

An earlier GRES attempt used:

```text
NVIDIA:GPU:L40S
```

The corrected Slurm resource identity was:

```text
gpu:L40S
```

### Lesson

Keep the GRES type consistent across:

```text
slurm.conf
      ↕
gres.conf
      ↕
srun/sbatch request
```

---

## 21.3 Deprecated cgroup options

The installed Slurm version rejected configuration options such as:

```text
CgroupAutomount
ConstrainKmemSpace
```

They were removed.

### Lesson

Configuration compatibility must be checked against the **actual Slurm version installed on the node**.

---

## 21.4 AccountingStorageTRES / GPU accounting dependency

GPU accounting configuration depends on the Slurm accounting subsystem. The manual single-node validation therefore established GPU allocation and isolation first; full accounting is intentionally deferred to the next phase.

The next phase will add:

```text
MariaDB
   ↓
slurmdbd
   ↓
slurmctld accounting integration
```

---

## 21.5 PMIx warning

The environment produced PMIx-related warnings because PMIx was not installed/configured.

This was intentionally deferred until MPI/NCCL work, where the complete process-launch and communication stack will be introduced.

### Lesson

Do not add every possible dependency to the base node simply because a warning exists. Introduce the dependency when the corresponding workload requires it, then validate the complete path.

---

# 22. Commands that are easy to misuse

A few command-level lessons were captured during Phase 01.

### Slurm controller health

Use:

```bash
scontrol ping
```

not:

```bash
scontrol -ping
```

### `slurmd` validation

The installed Slurm 23.11.4 package did not support:

```bash
slurmd -t
```

Useful alternatives were direct/debug daemon execution and service validation, for example:

```bash
slurmd -Dvvv
systemctl status slurmd
journalctl -u slurmd
```

### Study point

Always validate commands against the exact installed version instead of assuming command-line options are universal across Slurm releases.

---

# 23. GPU virtualization / SR-IOV study boundary

During PCIe investigation, the guest-visible link state raised a question about whether the L40S was being delivered through NVIDIA vGPU or another virtualization mechanism.

### What Phase 01 established

The guest clearly received an NVIDIA L40S through the cloud platform's GPU attachment/virtualization infrastructure.

The guest also exposed:

```text
PCIe capability: 16GT/s x16
Negotiated state: 2.5GT/s x16
```

### What Phase 01 did **not** establish

The guest-side evidence was not sufficient to prove that Nebius used:

- NVIDIA vGPU
- SR-IOV
- PCIe passthrough
- a mediated-device model
- dedicated physical allocation

These mechanisms must not be conflated.

```text
PCIe virtualization ≠ NVIDIA vGPU
SR-IOV          ≠ NVIDIA vGPU
SR-IOV          ≠ MIG
PCIe passthrough ≠ SR-IOV
```

### SR-IOV study point

**SR-IOV** means **Single Root I/O Virtualization**.

The basic PCIe model is:

```text
Physical PCIe device
        │
        ▼
Physical Function (PF)
        │
        ├──── Virtual Function (VF)
        ├──── Virtual Function (VF)
        └──── Virtual Function (VF)
```

SR-IOV allows a PCIe device to expose multiple virtual functions. In GPU environments, SR-IOV can participate in how virtual device instances are exposed, but SR-IOV itself does **not** define the GPU's compute/memory partitioning model.

This must be distinguished from:

```text
NVIDIA vGPU → GPU virtualization technology with profiles
MIG         → hardware GPU partitioning into isolated instances
```

### Future guest-side evidence

Useful commands for a future investigation include:

```bash
lspci -nn
lspci -vv -s <BDF>
lspci -vvv -s <BDF>
cat /sys/bus/pci/devices/<BDF>/vendor
cat /sys/bus/pci/devices/<BDF>/device
cat /sys/bus/pci/devices/<BDF>/sriov_totalvfs
cat /sys/bus/pci/devices/<BDF>/sriov_numvfs
readlink /sys/bus/pci/devices/<BDF>/driver
nvidia-smi -q
nvidia-smi -q -d PCI
nvidia-smi topo -m
```

Not every file exists in every virtualization mode. **Absence is itself evidence** and should be recorded.

### AI-factory relevance

The distinction matters because GPU virtualization affects how engineers reason about:

- PCIe topology and bandwidth
- DMA and device isolation
- NUMA locality
- NIC/GPU locality
- GPUDirect RDMA
- GPU assignment and scheduling
- performance troubleshooting

This topic will be revisited when networking and distributed GPU workloads are introduced.

---

# 24. What Phase 01 proved

Phase 01 successfully established the following layered foundation:

```text
Hardware / virtual GPU attachment
            ↓
PCIe visibility
            ↓
NVIDIA driver
            ↓
CUDA Toolkit / runtime
            ↓
Real CUDA execution
            ↓
GPU telemetry / topology
            ↓
MUNGE authentication
            ↓
Slurm slurmd
            ↓
GRES discovery
            ↓
cgroup v2 enforcement
            ↓
Slurm GPU scheduling
```

More specifically, the lab proved:

1. The L40S was visible to Linux.
2. The NVIDIA driver stack was operational.
3. CUDA Toolkit 13.0 was installed and usable.
4. CUDA code executed successfully on the real GPU.
5. GPU stress produced measurable hardware telemetry.
6. PCIe capability and negotiated state could be inspected.
7. NVIDIA topology showed the expected single-L40S/no-NVLink topology.
8. MUNGE authentication worked.
9. Slurm discovered the L40S through GRES.
10. CPU allocation reached Linux cpuset enforcement.
11. Memory allocation reached Linux cgroup memory enforcement.
12. GPU allocation reached device isolation and `CUDA_VISIBLE_DEVICES`.
13. End-to-end `srun` GPU allocation worked.

---

# 25. What Phase 01 intentionally did not prove

The following are explicitly deferred:

- Slurm accounting and historical usage
- MariaDB / SlurmDBD integration
- multi-node scheduling
- MPI / PMIx integration
- NCCL collectives
- InfiniBand
- GPUDirect RDMA
- multi-GPU topology
- distributed training
- checkpointing under failure
- production observability
- high-availability controller architecture
- automated node lifecycle
- exact Nebius host-side GPU virtualization mechanism

These are not gaps to be hidden; they define the next phases of the lab.

---

# 26. Phase 01 final state

The manual node:

```text
l40-node-01
```

was **deleted after the manual validation was complete**.

This is intentional.

The node was not converted into the next phase's compute node because doing so would blur the boundary between:

```text
manual reference implementation
```

and:

```text
reproducible automated implementation
```

The next L40S compute nodes will be fresh instances and will be configured by Ansible.

---

# 27. Next phase

## Phase 02 — Slurm Accounting Foundation

The next implementation step is to add accounting to the persistent controller:

```text
slurm-controller-01
        │
        ├── slurmctld
        ├── slurmdbd
        └── MariaDB
```

Target flow:

```text
Slurm jobs
    ↓
slurmctld
    ↓
slurmdbd
    ↓
MariaDB
    ↓
Historical job / cluster / association data
```

This accounting layer will be completed and validated **before** the final GPU nodes are rebuilt through Ansible.

---

# 28. Phase 01 study checklist

Before moving deeper into the AI-factory stack, the following concepts should be explainable without referring back to commands:

- PCIe device detection vs driver binding
- NVIDIA driver vs CUDA Toolkit vs CUDA runtime
- `nvidia-smi` vs actual CUDA execution
- GPU telemetry and utilization
- PCIe `LnkCap` vs `LnkSta`
- NUMA and CPU/GPU locality
- Slurm controller vs `slurmd` vs `slurmstepd`
- Slurm GRES and `gpu:L40S`
- MUNGE trust/authentication
- cgroup v2 resource enforcement
- CPU, memory, and GPU isolation
- SR-IOV, PF, VF
- PCIe passthrough vs SR-IOV vs vGPU vs MIG
- why L40S and HGX H100/H200 belong to different performance-study phases

---

## Reference commands

### NVIDIA

```bash
nvidia-smi
nvidia-smi -L
nvidia-smi dmon
nvidia-smi topo -m
nvidia-smi -q
nvidia-smi -q -d PCI
```

### CUDA

```bash
nvcc --version
```

### PCIe / Linux

```bash
lspci -nn
lspci -vv -s <BDF>
lspci -vvv -s <BDF>
lsmod | grep nvidia
ls -l /dev/nvidia*
```

### MUNGE

```bash
systemctl is-active munge
munge -n | unmunge
```

### Slurm

```bash
scontrol ping
sinfo
scontrol show node
slurmd -G
```

### cgroup v2

```bash
mount | grep cgroup
find /sys/fs/cgroup -maxdepth 4 -type d | head -50
```

---

## Final principle

> **The objective of Phase 01 was not to create a permanent GPU node. It was to understand and prove the interfaces between the GPU hardware layer, NVIDIA software stack, Slurm, MUNGE, and Linux cgroup enforcement well enough that the next implementation can be automated without turning the automation into a black box.**
