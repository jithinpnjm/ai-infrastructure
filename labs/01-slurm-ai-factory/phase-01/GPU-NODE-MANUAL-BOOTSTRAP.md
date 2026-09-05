# Lab 01 — Phase 01: Manual NVIDIA GPU Node Bootstrap

## Purpose

This document records the **manual GPU-node bootstrap performed before the cluster was moved toward Ansible-based configuration**.

The node documented here was an exploratory/reference node. Its purpose was to understand the NVIDIA GPU software and hardware stack, establish the relationship between Linux GPU devices and Slurm GRES, and prove the basic Slurm compute-node path manually.

This document is intentionally a **base reference**, not a final production design. Future phases will add and refine:

- Ansible implementation
- repeatable provisioning
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

Where something remains uncertain or was intentionally deferred, it is recorded rather than silently filled in. Future phases are expected to resolve these grey areas.

---

## 1. Role of the manual node

The first L40S compute node was deliberately configured manually.

The learning sequence was:

```text
Nebius GPU VM
     |
     v
Linux / PCIe
     |
     v
NVIDIA driver
     |
     v
NVIDIA kernel module + device nodes
     |
     v
CUDA Toolkit / CUDA runtime
     |
     v
Real CUDA workload
     |
     v
GPU telemetry / topology
     |
     v
MUNGE
     |
     v
Slurm slurmd
     |
     v
GRES discovery
     |
     v
cgroup v2 enforcement
     |
     v
Slurm GPU allocation
```

The node was **not intended to become the permanent production cluster node**. It was a reference implementation used to understand what the later Ansible automation must reproduce.

The node can therefore be deleted after this documentation is captured.

---

# 2. Nebius GPU VM baseline

## 2.1 Platform

The compute node was created on Nebius using an L40S GPU platform.

Relevant observed characteristics:

```text
GPU platform:     gpu-l40s-d
GPU:              NVIDIA L40S
GPU count:        1
CPU:              AMD EPYC Genoa
vCPU:             16
Memory:           ~96 GiB
Root disk:        200 GB SSD
OS:               Ubuntu 24.04.4
Kernel:           6.11.0-1016-nvidia
Private IP:       10.0.0.18
Hostname:         l40-node-01
```

The VM was intentionally started from a **driverless image** for this manual bootstrap. This allowed the NVIDIA driver installation and resulting software stack to be studied rather than hidden behind a preconfigured image.

The later Ansible phase will use the Nebius preconfigured GPU image for the new nodes. That is a deliberate change in methodology, not an inconsistency.

---

# 3. Initial hardware discovery

Before installing the NVIDIA software stack, the node should be treated as a normal Linux host and its hardware inspected.

Useful baseline commands:

```bash
uname -a
cat /etc/os-release
lscpu
free -h
lsblk
lspci -nn
lspci -nn | grep -i -E 'nvidia|3d|vga'
```

The important study point is the distinction between:

```text
PCIe device exists
        |
        v
Linux kernel recognizes the device
        |
        v
NVIDIA kernel driver binds to it
        |
        v
/dev/nvidia* devices appear
        |
        v
nvidia-smi can communicate with the GPU
        |
        v
CUDA can execute work on the GPU
```

A GPU being visible in `lspci` does **not** prove that CUDA or NVIDIA management functionality is operational.

---

# 4. NVIDIA driver bootstrap

## 4.1 Driver installation

The node initially did not have a working NVIDIA driver stack.

The package resolution selected the Ubuntu NVIDIA server-driver package:

```text
nvidia-driver-570-server
```

The resulting installed DKMS driver was:

```text
nvidia-srv/580.173.02
```

The effective driver reported by `nvidia-smi` was:

```text
Driver Version: 580.173.02
CUDA Version:   13.0
```

The package name and actual kernel-driver version should not be assumed to be identical. Package metadata, DKMS module version, and `nvidia-smi` reported driver version are separate things that should be checked during troubleshooting.

## 4.2 Driver validation

Primary validation:

```bash
nvidia-smi
nvidia-smi -L
lsmod | grep nvidia
ls -l /dev/nvidia*
```

The successful state showed the L40S through `nvidia-smi` and exposed the NVIDIA device nodes.

### Study point

A useful troubleshooting chain is:

```text
lspci
  -> kernel/device detection

lsmod
  -> NVIDIA kernel module

/dev/nvidia*
  -> device interface

nvidia-smi
  -> NVIDIA management stack

CUDA test
  -> actual compute/runtime functionality
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

The CUDA environment was made available through `/etc/profile.d/cuda.sh`.

The important distinction is:

```text
NVIDIA driver
        !=
CUDA Toolkit
        !=
CUDA application/runtime
```

The driver is responsible for communicating with the GPU and supporting CUDA execution. The toolkit provides development/runtime components such as `nvcc` and CUDA libraries needed to build and run CUDA applications.

A system can have a functioning NVIDIA driver while `nvcc` is unavailable.

---

# 6. Real CUDA validation

A CUDA device-query test was used to verify the actual GPU from CUDA rather than merely checking `nvidia-smi`.

Observed result:

```text
GPU count:       1
GPU:             NVIDIA L40S
Compute Capability: 8.9
Memory:          ~44.39 GiB
```

A real CUDA vector-add operation was then executed.

The result was:

```text
3.0
```

This was important because it proved an actual CUDA kernel execution path rather than only device enumeration.

## Validation hierarchy

```text
nvidia-smi
    |
    | management visibility
    v
CUDA device query
    |
    | runtime/device visibility
    v
CUDA vector addition
    |
    | actual kernel execution
    v
GPU workload
```

This pattern should be retained for future GPU-node validation.

---

# 7. GPU stress and telemetry baseline

A GPU stress workload was executed to establish a real utilization baseline.

Observed behavior included approximately:

```text
SM utilization:       100%
Memory utilization:   100%
Power:                ~230–231 W
Temperature:          ~56–57 C
VRAM used:            ~3.5 GiB
GPU clock:            ~2520 MHz
Memory clock:         ~9001 MHz
```

The exact values are workload- and environment-dependent; they are recorded here as observations from this node, not universal L40S specifications.

Useful commands:

```bash
nvidia-smi
nvidia-smi dmon
nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,utilization.memory,memory.used,memory.total,clocks.sm,clocks.mem --format=csv
```

### Study point

A useful AI-infrastructure validation principle is:

> Do not stop at “GPU is visible.” Drive the GPU and verify that the hardware, driver, power, clocks, temperature and memory path behave as expected.

Future phases should turn these observations into automated health checks and monitoring.

---

# 8. PCIe baseline

The L40S is a PCIe GPU and does not use NVLink in this configuration.

The PCIe capability and negotiated link were inspected using:

```bash
lspci -vv
```

The GPU reported capability equivalent to:

```text
LnkCap: 16GT/s x16
```

but the negotiated link was observed as:

```text
LnkSta: 2.5GT/s x16
```

Therefore the virtualized environment exposed the device with an observed **PCIe Gen1 x16 negotiated link**, despite the device capability being higher.

This was recorded as an environment observation. We did not attempt to force or repair the negotiated PCIe generation.

### Study point

Always distinguish:

```text
LnkCap = what the device/link supports
LnkSta = what is currently negotiated
```

A GPU can therefore be healthy while the effective PCIe bandwidth is lower than the physical device capability.

This becomes especially important for:

- CPU-to-GPU transfers
- data loading
- GPUDirect paths
- multi-GPU communication
- NCCL performance

The PCIe baseline should be rechecked in later phases when performance benchmarking is introduced.

---

# 9. NVIDIA topology

The topology was inspected with:

```bash
nvidia-smi topo -m
```

Observed characteristics:

```text
GPU0 CPU Affinity: 0-15
NUMA:               0
NVLink:             none
```

The L40S therefore represents a different topology class from the later H100/H200 HGX nodes.

### Important architectural distinction

The future lab will use different GPU classes for different learning objectives:

```text
L40S
  -> PCIe GPU
  -> no NVLink
  -> useful for Slurm/GPU scheduling and PCIe-based workloads

H100/H200 HGX
  -> 8-GPU NVLink/SXM systems
  -> InfiniBand
  -> useful for multi-GPU/NCCL/collective-performance studies
```

We should not attempt to infer NVLink behavior from the L40S node. That belongs to the later HGX/NCCL phase.

---

# 10. MUNGE bootstrap

Slurm uses MUNGE authentication in this lab.

The controller and compute node must share the same MUNGE trust domain.

The critical property is the shared key:

```text
/etc/munge/munge.key
```

The key was transferred to the compute node and installed with:

```text
owner:  munge:munge
mode:   0400
```

The SHA-256 hash of the controller and compute-node keys was verified to be identical:

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

MUNGE is not a GPU mechanism and does not perform scheduling. It is part of the **authentication/trust layer** required for Slurm daemon communication.

Conceptually:

```text
slurmctld
    |
    | authenticated Slurm RPC
    v
slurmd
    |
    v
MUNGE trust
```

Later phases should cover stronger security architecture, key distribution and secret-management automation.

---

# 11. Slurm compute-node bootstrap

After the underlying GPU stack was proven, the node was integrated with Slurm.

The node ran:

```text
slurmd 23.11.4
```

The cluster identity was:

```text
ai-factory-lab
```

The node was:

```text
l40-node-01
```

and belonged to the:

```text
gpu
```

partition.

The controller's logical GPU resource was:

```text
gpu:L40S
```

The node-local GRES mapping was:

```text
Name=gpu Type=L40S File=/dev/nvidia0
```

---

# 12. Physical GPU → Slurm GRES mapping

This is one of the most important concepts established during the manual build.

The physical GPU appears to Linux as a device such as:

```text
/dev/nvidia0
```

NVIDIA identifies the device as:

```text
NVIDIA L40S
```

Slurm represents it as a logical Generic RESource:

```text
gpu:L40S
```

The relationship is:

```text
Physical GPU
NVIDIA L40S
      |
      v
Linux device
/dev/nvidia0
      |
      v
Slurm gres.conf
Name=gpu Type=L40S File=/dev/nvidia0
      |
      v
Slurm controller
Gres=gpu:L40S
      |
      v
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

An earlier configuration attempt used an incorrect hierarchical interpretation and did not match the expected Slurm GRES syntax. The final configuration uses:

```text
gpu:L40S
```

This naming relationship must remain consistent across the controller configuration, `gres.conf`, and job request.

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

```text
Name   = gpu
Type   = L40S
Count  = 1
Index  = 0
File   = /dev/nvidia0
```

This is a useful boundary test:

```text
NVIDIA stack works
        ↓
Linux device exists
        ↓
Slurm GRES configuration parses
        ↓
slurmd discovers the GPU
```

If `slurmd -G` does not report the expected GPU, the problem should be investigated before debugging scheduler allocation.

---

# 14. cgroup v2 foundation

The compute node used Linux cgroup v2 through:

```text
/sys/fs/cgroup
```

The relevant Slurm configuration was:

```ini
TaskPlugin=task/cgroup
CgroupMountpoint=/sys/fs/cgroup
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedSwapSpace=200
```

The purpose is to turn Slurm's resource allocation into local kernel-enforced restrictions.

Conceptually:

```text
Slurm scheduler
     |
     | allocation decision
     v
slurmd / slurmstepd
     |
     | create/manage cgroups
     v
Linux cgroup v2
     |
     +--> CPU restriction
     +--> memory restriction
     +--> device/GPU restriction
     +--> process containment/cleanup
```

### Important principle

> Slurm decides what resources a job receives; Linux cgroups enforce those decisions on the compute node.

---

# 15. cgroup v2 configuration compatibility issue

The example configuration shipped with the installed Slurm package contained options that were not accepted by the installed Slurm version.

The problematic options included:

```text
CgroupAutomount
ConstrainKmemSpace
```

`slurmd` initially failed while parsing the configuration.

The obsolete options were removed and the node recovered.

### Operational lesson

Never assume that a configuration example found in documentation, package files, or an older Slurm deployment is valid for the exact installed version.

The correct workflow is:

```text
Installed version
       ↓
Version-specific documentation
       ↓
Configuration
       ↓
Parser/service validation
       ↓
Runtime validation
```

This lesson will be important when the configuration is converted into Ansible templates.

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

The result was:

```text
0-3
```

representing four CPUs.

### What this proves

Slurm's CPU allocation was translated into a Linux cpuset restriction.

This is stronger than checking only:

```bash
echo $SLURM_CPUS_ON_NODE
```

because an environment variable describes the allocation to the application, whereas `cpuset.cpus.effective` demonstrates kernel-level CPU confinement.

---

# 17. Memory enforcement validation

The job requested:

```text
--mem=4096M
```

The leaf task cgroup initially showed:

```text
memory.max=max
memory.high=max
```

This initially appeared to indicate that the memory limit was missing.

Inspection of the parent cgroup showed:

```text
memory.max  = 4294967296
memory.high = 4294967296
```

and:

```text
4294967296 bytes = 4096 MiB
```

### Lesson

With cgroup v2 and the Slurm/systemd hierarchy, a limit does not necessarily have to appear on the leaf task cgroup.

When debugging resource enforcement, inspect the hierarchy:

```text
systemd scope
   ↓
job
   ↓
step
   ↓
user
   ↓
task
```

Do not conclude that enforcement is missing from a single leaf inspection.

---

# 18. GPU allocation validation

A GPU job was launched with:

```bash
srun -p gpu --gres=gpu:L40S:1 --pty bash
```

Inside the job:

```bash
echo "$CUDA_VISIBLE_DEVICES"
nvidia-smi -L
```

The observed state included:

```text
CUDA_VISIBLE_DEVICES=0
GPU 0: NVIDIA L40S
```

### What this proves

The following chain was operational:

```text
Slurm job request
      ↓
GRES scheduler allocation
      ↓
slurmd/slurmstepd
      ↓
GPU device confinement
      ↓
CUDA-visible GPU
      ↓
NVIDIA runtime access
```

---

# 19. No-GPU isolation validation

A separate job was launched without requesting a GPU:

```bash
srun -p gpu --cpus-per-task=2 --mem=1G --pty bash
```

Inside that job:

```bash
echo "$CUDA_VISIBLE_DEVICES"
nvidia-smi -L
```

The observed result was:

```text
CUDA_VISIBLE_DEVICES=
No devices found.
```

### Why this test matters

This validates **negative isolation**, not only positive allocation.

A successful GPU job proves:

> A job that requests a GPU can access it.

The no-GPU test proves:

> A job that does not request a GPU cannot simply access the node's GPU.

This is an important production-style validation pattern for shared GPU infrastructure.

---

# 20. Slurm cgroup hierarchy observed

A real Slurm task showed a cgroup path similar to:

```text
/system.slice/l40-node-01_slurmstepd.scope/job_6/step_0/user/task_0
```

Conceptually:

```text
/system.slice/
  └── l40-node-01_slurmstepd.scope/
       └── job_<id>/
            └── step_0/
                 └── user/
                      └── task_0/
```

The important conceptual model is:

```text
Job
  = scheduler allocation

Step
  = execution unit within the job

Task
  = launched workload unit/process group
```

The exact hierarchy can vary with Slurm and systemd configuration. Future phases should investigate the complete process/cgroup lifecycle during batch jobs, multi-task jobs and distributed training.

---

# 21. Controller ↔ compute-node relationship

The manual work established an important separation of responsibilities.

```text
+----------------------------+
| slurm-controller-01        |
|                            |
| slurmctld                  |
| Scheduling/control         |
| Cluster configuration      |
+-------------+--------------+
              |
              | Slurm RPC
              | authenticated by MUNGE
              v
+----------------------------+
| l40-node-01                |
|                            |
| slurmd                     |
| slurmstepd                 |
| NVIDIA driver/CUDA         |
| GRES                       |
| Linux cgroup v2            |
| Actual workload            |
+----------------------------+
```

The controller knows what resources are configured.

The compute node is where those resources physically exist and where Linux enforces restrictions.

This distinction is foundational for later topics such as:

- node registration
- drain states
- GRES failures
- cgroup failures
- GPU health failures
- distributed jobs
- node lifecycle automation

---

# 22. Node registration model

The controller configured the node approximately as:

```ini
NodeName=l40-node-01 \
  NodeAddr=10.0.0.18 \
  NodeHostname=l40-node-01 \
  CPUs=16 \
  Boards=1 \
  SocketsPerBoard=1 \
  CoresPerSocket=8 \
  ThreadsPerCore=2 \
  RealMemory=96556 \
  Gres=gpu:L40S \
  State=UNKNOWN
```

The registered node eventually reported:

```text
CPUTot=16
RealMemory=96556
Gres=gpu:L40S:1
State=IDLE
```

### Study point

There is a difference between:

```text
configured node
```

and:

```text
registered/healthy node
```

The controller configuration describes what the cluster expects.

`slurmd` reports what the compute node actually provides.

A mismatch can result in registration errors, invalid resource states, or node draining.

---

# 23. Cluster-name mismatch incident

During the manual configuration, the cluster name was initially different from the final intended name.

The cluster was initially initialized with a different identity and later changed to:

```ini
ClusterName=ai-factory-lab
```

Slurm detected persistent state associated with the previous identity and reported:

```text
CLUSTER NAME MISMATCH
```

The stale cluster-name state was removed and `slurmctld` was restarted using the intended configuration.

The final cluster name is:

```text
ai-factory-lab
```

### Lesson

Treat `ClusterName` as persistent cluster identity, not as a cosmetic label.

Once Slurm state exists, changing the name can create a state/identity mismatch.

Future automation should make the cluster identity explicit and stable.

---

# 24. Slurm command/version lessons

A few operational details were learned during the manual phase.

### Correct controller health command

Use:

```bash
scontrol ping
```

rather than:

```bash
scontrol -ping
```

### `slurmd -t`

The installed Slurm 23.11.4 build did not provide the expected `slurmd -t` validation command.

Useful alternatives include:

```bash
slurmd -G
slurmd -Dvvv
systemctl status slurmd
journalctl -u slurmd
```

### Study point

Commands should be validated against the installed Slurm version rather than assumed from older tutorials or other distributions.

---

# 25. PMIx warning — intentionally deferred

Slurm 23.11.4 reported warnings around:

```text
mpi/pmix
mpi/pmix_v5
```

because PMIx was not installed.

This did not block the single-node Slurm/GPU foundation.

PMIx/MPI integration was intentionally deferred until the distributed workload phase.

This is not considered a resolved configuration item yet.

Future work should establish:

```text
PMIx
MPI
Slurm launch
NCCL
multi-process GPU communication
```

and determine the correct production-like process-launch model for distributed training.

---

# 26. Accounting was intentionally deferred

Basic Slurm GPU scheduling was validated without introducing SlurmDBD at this stage.

An attempted configuration involving GPU accounting TRES caused `slurmctld` to require SlurmDBD.

The problematic accounting configuration was removed for the foundation phase.

The next phase will deliberately introduce:

```text
MariaDB
   ↓
slurmdbd
   ↓
slurmctld
   ↓
sacctmgr
   ↓
cluster/account/user associations
   ↓
job accounting
```

This is a deliberate phase boundary, not an architectural omission.

---

# 27. Complete manual validation matrix

| Layer | Validation | Observed result | Confidence |
|---|---|---|---|
| OS | Ubuntu/kernel inspection | Ubuntu 24.04.4 / 6.11.0-1016-nvidia | Proven |
| Hardware | `lspci` | L40S visible | Proven |
| NVIDIA module | `lsmod` | NVIDIA module loaded | Proven |
| Device nodes | `/dev/nvidia*` | NVIDIA devices present | Proven |
| Driver | `nvidia-smi` | Driver 580.173.02 | Proven |
| GPU | `nvidia-smi -L` | L40S visible | Proven |
| CUDA compiler | `nvcc --version` | CUDA 13.0 / 13.0.88 | Proven |
| CUDA runtime | device query | L40S / CC 8.9 | Proven |
| CUDA compute | vector add | result 3.0 | Proven |
| GPU stress | utilization/power/temp | real GPU load observed | Proven |
| PCIe | `lspci -vv` | x16 capability / Gen1 x16 observed | Proven observation |
| Topology | `nvidia-smi topo -m` | CPU/NUMA affinity, no NVLink | Proven observation |
| MUNGE | `munge  ` | Success | Proven |
| Slurm daemon | `slurmd` | operational | Proven |
| GRES | `slurmd -G` | `gpu:L40S`, `/dev/nvidia0` | Proven |
| Registration | `sinfo` / `scontrol show node` | node IDLE | Proven |
| GPU allocation | `srun --gres=gpu:L40S:1` | GPU visible | Proven |
| GPU isolation | no-GPU `srun` | GPU unavailable | Proven |
| CPU cgroup | `cpuset.cpus.effective` | four-CPU restriction | Proven |
| Memory cgroup | parent `memory.max` | 4096 MiB restriction | Proven |
| Accounting | SlurmDBD | deferred | Not yet implemented |
| PMIx | MPI/PMIx | deferred | Not yet implemented |
| Multi-node | distributed workload | deferred | Not yet implemented |
| NCCL | collectives/performance | deferred | Not yet implemented |
| InfiniBand | fabric validation | deferred | Not yet implemented |
| GPUDirect RDMA | validation | deferred | Not yet implemented |

---

# 28. What this phase actually proved

The manual build proved the complete **single-node GPU + Slurm foundation**:

```text
Nebius L40S VM
      ↓
Linux hardware detection
      ↓
NVIDIA driver
      ↓
CUDA Toolkit
      ↓
Real CUDA execution
      ↓
GPU telemetry/topology
      ↓
MUNGE
      ↓
Slurm slurmd
      ↓
GRES discovery
      ↓
Node registration
      ↓
Slurm allocation
      ↓
cgroup v2 enforcement
      ↓
Actual constrained GPU workload
```

That is the baseline from which subsequent phases should build.

---

# 29. What remains intentionally unknown / grey areas

The manual phase is **not** considered complete knowledge of a production AI factory.

Important areas remain open:

### GPU infrastructure

- GPU reset/recovery behavior
- persistence mode and production policy
- ECC/error monitoring
- XID error handling
- DCGM
- GPU health checks
- GPU failure isolation
- MIG vs time-sharing
- GPU sharing semantics

### PCIe / topology

- performance impact of the observed virtualized PCIe negotiation
- NUMA-aware CPU placement
- PCIe locality on multi-GPU hosts
- GPUDirect-related topology requirements

### Slurm

- advanced GRES configuration
- `AutoDetect` behavior across GPU generations
- GPU binding
- CPU/GPU affinity
- `--gpus`, `--gres`, and related GPU allocation semantics
- reservations
- QoS
- priorities
- fair-share
- preemption
- job arrays
- advanced scheduling
- node health checks
- drain/undrain lifecycle

### cgroups

- complete cgroup v2 hierarchy behavior
- memory OOM behavior
- swap policy
- process cleanup
- device ACL implementation details
- interaction with systemd
- batch vs interactive differences

### Distributed AI

- PMIx
- MPI
- NCCL
- topology-aware NCCL
- TCP vs InfiniBand transport
- GPUDirect RDMA
- multi-node process launch
- distributed checkpointing
- failed-rank recovery

### Operations

- SlurmDBD/MariaDB production design
- accounting and associations
- secrets management
- Ansible idempotency
- node replacement
- automated GPU-node provisioning
- observability
- alerting
- backup/recovery
- controller HA

These are deliberately carried forward as learning objectives rather than guessed at in Phase 01.

---

# 30. Manual implementation → Ansible desired state

The manual node now serves as the reference model for the next phase.

The future automated state should reproduce the required functional properties, not merely reproduce the exact shell commands.

```text
Manual reference node
        |
        | lessons / validated state
        v
Ansible desired state
        |
        +--> common OS configuration
        +--> NVIDIA baseline (where applicable)
        +--> MUNGE
        +--> Slurm common configuration
        +--> controller configuration
        +--> SlurmDBD
        +--> MariaDB
        +--> compute-node configuration
        +--> GRES
        +--> cgroups
        +--> validation
        |
        v
l40-node-01 + l40-node-02
```

The Ansible implementation should be idempotent and version-aware.

Manual commands remain useful as troubleshooting tools, but the desired cluster state should live in Git-managed configuration.

---

# 31. Future phase documentation rule

From this point onward, changes should be recorded incrementally rather than rewriting history.

For each significant phase, document:

1. **Initial state**
2. **Why a change is needed**
3. **Design decision**
4. **Configuration change**
5. **Commands used**
6. **Observed output/result**
7. **Validation**
8. **Failure/issue encountered**
9. **Root cause**
10. **Remediation**
11. **What changed architecturally**
12. **What is still unknown**
13. **Study points**
14. **How the change will be automated/rebuilt**

This keeps the repository useful both as an operational record and as a progressive AI-infrastructure study guide.

---

# 32. Base study model

The foundation should be remembered as five layers:

```text
Layer 1 — Hardware
    GPU / PCIe / CPU / NUMA / memory

Layer 2 — NVIDIA software
    Driver / kernel modules / CUDA / device nodes

Layer 3 — Cluster security
    MUNGE / trust / daemon authentication

Layer 4 — Slurm
    slurmctld / slurmd / GRES / scheduler / allocation

Layer 5 — Linux enforcement
    cgroup v2 / CPU / memory / device isolation
```

Later phases add:

```text
Layer 6 — Accounting
    MariaDB / slurmdbd / associations / usage

Layer 7 — Automation
    Ansible / Git / reproducibility

Layer 8 — Multi-node networking
    Ethernet / InfiniBand / NCCL / GPUDirect RDMA

Layer 9 — Distributed AI workload
    PyTorch / torchrun / NCCL / datasets / checkpoints

Layer 10 — Production operations
    observability / failure handling / HA / lifecycle / recovery
```

The objective is not merely to operate each layer independently. The objective is to understand the **interfaces between layers** and how a failure at one layer propagates upward.

For example:

```text
GPU driver failure
      ↓
GPU discovery failure
      ↓
GRES mismatch
      ↓
node registration/scheduling problem
      ↓
GPU job cannot be allocated
```

or:

```text
Slurm allocation
      ↓
cgroup configuration
      ↓
CPU/memory/GPU enforcement
      ↓
workload behavior
```

That layered reasoning will be the basis for troubleshooting in all later phases.

---

## Status

**Phase 01 manual GPU + Slurm foundation: completed and documented.**

The original manual L40S node is now considered a **reference implementation** and may be destroyed.

The next implementation phase will introduce **MariaDB + SlurmDBD**, followed by the Ansible architecture and two fresh L40S compute nodes configured from code.
