# Lab 01 — Phase 01: Slurm Foundation and Resource Isolation

## Purpose

This document records the **actual configuration and validation path** used to make the first Slurm AI-factory node functional.

The goal is understanding, not just deployment. Every major configuration item below records:

1. What was configured
2. Why it exists
3. What was tested
4. What the test proves

Support/workaround activities such as copying files through the local workstation are intentionally **not** documented as architecture steps.

---

## 1. Final topology

```text
                         Slurm cluster: ai-factory-lab

                  +-----------------------------+
                  | slurm-controller-01         |
                  | Ubuntu 24.04                |
                  | slurmctld 23.11.4           |
                  | MUNGE                       |
                  | slurm.conf                  |
                  +-------------+---------------+
                                |
                         Slurm RPC / MUNGE
                                |
                                v
                  +-----------------------------+
                  | l40-node-01                 |
                  | Ubuntu 24.04                |
                  | slurmd 23.11.4             |
                  | NVIDIA L40S                 |
                  | cgroup v2 + systemd         |
                  | gres.conf / cgroup.conf     |
                  +-----------------------------+
```

The controller schedules resources. The compute node runs the workload and performs the actual local resource enforcement through `slurmd` and Linux cgroups.

---

## 2. Slurm cluster identity

### Configuration

```ini
ClusterName=ai-factory-lab
```

### Meaning

`ClusterName` is the persistent identity of the Slurm cluster. `slurmctld` stores state associated with this identity.

### What happened

The cluster was initially initialized with a different name and later changed. Slurm detected the persistent-state mismatch and reported:

```text
CLUSTER NAME MISMATCH
```

The cluster identity was deliberately accepted and is now treated as fixed.

### Lesson

Do not casually change `ClusterName` after Slurm state has been initialized. A cluster-name change can be interpreted as state belonging to a different cluster.

---

## 3. Slurm authentication with MUNGE

### Configuration

```ini
AuthType=auth/munge
```

MUNGE is running on both controller and compute node with the same authentication key.

### Meaning

Slurm daemons use MUNGE credentials to authenticate Slurm RPC communication. The shared MUNGE key establishes a common trust domain between cluster nodes.

### Validation performed

```bash
systemctl is-active munge
munge -n | unmunge
```

The result was:

```text
STATUS: Success (0)
```

### What it proves

- MUNGE is operational.
- The node can create and validate a MUNGE credential.
- The authentication layer required by Slurm is functional.

---

## 4. Slurm controller

### Configuration

```ini
SlurmctldHost=slurm-controller-01
```

### Validation

```bash
systemctl is-active slurmctld
scontrol ping
```

Result:

```text
active
Slurmctld(primary) at slurm-controller-01 is UP
```

### What it proves

`slurmctld` is running and accepting Slurm control requests. It is the scheduling/control-plane daemon for the cluster.

---

## 5. Partition

### Configuration

A `gpu` partition was configured with `l40-node-01` as its node.

### Validation

```bash
sinfo
```

Result:

```text
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
gpu*         up   infinite      1   idle l40-node-01
```

### What it proves

The controller knows about the compute node, the node is assigned to the GPU partition, and it is currently available for scheduling.

---

## 6. GRES — GPU as a schedulable resource

### Controller configuration

```ini
GresTypes=gpu
NodeName=l40-node-01 ... Gres=gpu:L40S State=UNKNOWN
```

### Node configuration

`gres.conf` identifies the physical GPU as:

```text
Name=gpu Type=L40S File=/dev/nvidia0
```

The important detail is the **matching GRES type**:

```text
gpu:L40S
```

The NVIDIA device name `NVIDIA L40S` must not be converted into a hierarchical Slurm name such as `NVIDIA:GPU:L40S`. Slurm GRES syntax here is `gpu:<type>`.

### Validation

```bash
slurmd -G
```

Reported:

```text
Gres Name=gpu Type=L40S Count=1 Index=0 ID=... File=/dev/nvidia0
```

The controller reported:

```text
Gres=gpu:L40S:1
```

### What it proves

Slurm successfully discovers the physical L40S and associates `/dev/nvidia0` with the logical Slurm resource `gpu:L40S`.

---

## 7. CPU topology registration

The compute node reports:

```text
CPUs=16
SocketsPerBoard=1
CoresPerSocket=8
ThreadsPerCore=2
RealMemory=96556
```

These values were explicitly represented in the controller's `NodeName` configuration.

### Why this matters

Slurm needs a consistent view of node topology to schedule CPU resources correctly. A mismatch can put a node into an unhealthy state or cause incorrect resource accounting.

### Validation

```bash
scontrol show node l40-node-01
```

Final state included:

```text
CPUTot=16
RealMemory=96556
State=IDLE
ThreadsPerCore=2
```

---

## 8. Slurm resource selection

### Final configuration

```ini
SelectType=select/cons_tres
SelectTypeParameters=CR_CORE_MEMORY
```

### Meaning

`select/cons_tres` makes Slurm's resource selection TRES-aware and allows resources such as CPUs and memory to be allocated as consumable resources.

`CR_CORE_MEMORY` means CPU cores and memory are consumable scheduling resources.

### Important distinction

GPU GRES registration does **not** require adding `gres/gpu` to `AccountingStorageTRES` for this lab's basic scheduling path.

An attempted configuration of:

```ini
AccountingStorageTRES=...,gres/gpu
```

caused `slurmctld` to fail because GPU TRES accounting in this configuration requires `slurmdbd`.

That line was removed. GPU scheduling through GRES continues to work without introducing `slurmdbd` at this stage.

---

# 9. Linux cgroup v2 foundation

## 9.1 Why cgroups are needed

Slurm is the **resource allocator/scheduler**. Linux cgroups are the **kernel enforcement mechanism**.

Without cgroups, Slurm can decide:

> Job A gets 4 CPUs and 4 GiB RAM.

But the operating system still needs a mechanism to constrain the processes so they cannot consume resources outside that allocation.

For this lab, cgroup enforcement is used for:

- CPU placement/confinement
- memory limits
- GPU device visibility/access
- process membership and cleanup

The system uses **cgroup v2**:

```text
/sys/fs/cgroup
```

and the job hierarchy is integrated with systemd.

---

## 9.2 Slurm task plugin

### Configuration on controller and compute node

```ini
TaskPlugin=task/cgroup
```

### Why it is present on both

`slurmctld` consumes the cluster configuration, while `slurmd` on the compute node actually launches tasks and applies the task cgroup behavior locally.

The compute node is where the Linux cgroup hierarchy is created and where the workload processes are placed into it.

### Validation

```bash
scontrol show config | grep -Ei 'TaskPlugin|Cgroup|Proctrack'
```

Result included:

```text
TaskPlugin              = task/cgroup
CgroupMountpoint        = /sys/fs/cgroup
CgroupPlugin            = autodetect
```

---

## 9.3 cgroup.conf

The final relevant configuration is:

```ini
CgroupMountpoint=/sys/fs/cgroup
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedSwapSpace=200
```

### Important package-version lesson

The example `cgroup.conf` shipped with this Slurm package contained options that are no longer accepted by the installed Slurm version:

```text
CgroupAutomount
ConstrainKmemSpace
```

`slurmd` initially failed with parsing errors. Those obsolete options were removed.

This is a useful operational lesson: **always validate example configuration against the installed Slurm version rather than copying an example blindly.**

---

# 10. Understanding the cgroup hierarchy

A real allocated task showed:

```text
0::/system.slice/l40-node-01_slurmstepd.scope/job_6/step_0/user/task_0
```

This is cgroup v2's unified hierarchy.

Conceptually:

```text
/system.slice/
  └── l40-node-01_slurmstepd.scope/
       └── job_6/
            └── step_0/
                 └── user/
                      └── task_0/
```

## What each level means

### `slurmstepd.scope`

The systemd scope containing the Slurm step daemon and its managed workload hierarchy on the compute node.

### `job_6`

The cgroup representing the Slurm job allocation. A job is the scheduler-level unit submitted by a user through commands such as `srun` or `sbatch`.

Example:

```bash
srun --cpus-per-task=4 --mem=4096M ...
```

creates a Slurm job allocation with a job ID.

### `step_0`

A **job step** is an execution unit within a Slurm job. A job can contain multiple steps.

For example, an interactive `srun` execution creates a step. Batch workflows can create multiple steps within the same job.

The step is important because resource enforcement can be applied to the processes belonging to that step.

### `user`

A cgroup level used by Slurm's task/cgroup hierarchy to organize the user processes within the step.

### `task_0`

The task-level cgroup for an individual Slurm task/process group. In a single-task interactive shell this commonly represents the shell/task launched by Slurm.

The exact hierarchy can vary with Slurm/systemd configuration, but the key concept is:

```text
Job = scheduler allocation
Step = execution unit inside the job
Task = individual launched workload unit
```

---

# 11. CPU enforcement test

A job was requested with:

```bash
srun -p gpu --gres=gpu:L40S:1 --cpus-per-task=4 --mem=4096M --pty bash
```

Inside the task cgroup:

```bash
cat /sys/fs/cgroup$CG/cpuset.cpus.effective
```

returned:

```text
0-3
```

and:

```text
CPUS=4
```

### What it proves

The Slurm CPU allocation is translated into a Linux cpuset restriction. The workload is confined to four CPUs rather than merely being told that it has four CPUs.

This is actual kernel-level enforcement.

---

# 12. Memory enforcement test

The same allocation requested:

```text
--mem=4096M
```

The task-level cgroup itself reported:

```text
memory.max=max
memory.high=max
```

Initially this looked like missing enforcement.

Inspection of the parent cgroup showed:

```text
job_6/step_0/user/

memory.max  = 4294967296
memory.high = 4294967296
```

`4294967296` bytes = 4096 MiB.

### What it proves

Memory enforcement is present at the step/user cgroup level and inherited by the task hierarchy.

This is an important cgroup v2/systemd hierarchy lesson: **do not assume the leaf task cgroup must contain every limit directly. Inspect the relevant parent cgroups.**

---

# 13. GPU device isolation

## GPU allocation test

With:

```bash
srun -p gpu --gres=gpu:L40S:1 --pty bash
```

inside the job:

```text
CUDA_VISIBLE_DEVICES=0
GPU 0: NVIDIA L40S
```

### What it proves

The Slurm GRES allocation correctly exposes the requested GPU to the workload.

## No-GPU test

A second job was launched without a GPU request:

```bash
srun -p gpu --cpus-per-task=2 --mem=1G --pty bash
```

Inside that job:

```text
CUDA_VISIBLE_DEVICES=
No devices found.
```

### What it proves

`ConstrainDevices=yes` is functioning with Slurm GRES. A job that did not request the GPU could not use the L40S through `nvidia-smi`.

This is stronger evidence than checking `/dev/nvidia0` with `ls`, because device nodes can exist in the filesystem while access is still restricted by cgroup/device policy.

---

# 14. End-to-end resource flow

The current architecture can be understood as:

```text
User request
    |
    | srun --cpus-per-task=4 --mem=4096M --gres=gpu:L40S:1
    v
+----------------------+
| slurmctld             |
| Scheduling             |
| - CPU                  |
| - memory               |
| - GRES GPU             |
+----------+-------------+
           |
           | allocation
           v
+----------------------+
| slurmd / slurmstepd   |
| on l40-node-01        |
+----------+-------------+
           |
           | create/manage task hierarchy
           v
+----------------------+
| Linux cgroup v2       |
|                       |
| cpuset -> CPU         |
| memory -> RAM         |
| devices -> GPU access |
+----------+-------------+
           |
           v
       Workload
```

The key principle is:

> **Slurm decides what the job is allowed to consume; Linux cgroups enforce that decision on the compute node.**

---

# 15. PMIx warning — intentionally deferred

Slurm 23.11.4 reports that `mpi/pmix` / `mpi/pmix_v5` cannot load PMIx because the PMIx library is not currently installed.

This does not block the current single-node Slurm/GPU foundation.

PMIx/MPI will be addressed when the lab reaches distributed training and MPI/NCCL process-launch integration.

---

# 16. Commands used for operational validation

### Controller health

```bash
systemctl is-active slurmctld
scontrol ping
sinfo
```

### Node state

```bash
scontrol show node l40-node-01
```

### Slurm resource configuration

```bash
scontrol show config | grep -Ei 'GresTypes|SelectType|SelectTypeParameters|TaskPlugin|Cgroup|Proctrack'
```

### GRES discovery

```bash
slurmd -G
```

### Job allocation

```bash
srun -p gpu --gres=gpu:L40S:1 --pty bash
```

### Job cgroup

```bash
cat /proc/self/cgroup
CG=$(awk -F: '$1=="0"{print $3}' /proc/self/cgroup)
cat /sys/fs/cgroup$CG/cpuset.cpus.effective
cat /sys/fs/cgroup$CG/memory.max
```

### Job environment

```bash
echo "$SLURM_JOB_ID"
echo "$SLURM_CPUS_ON_NODE"
echo "$SLURM_MEM_PER_NODE"
echo "$CUDA_VISIBLE_DEVICES"
```

### GPU visibility

```bash
nvidia-smi -L
```

---

# 17. Current proven state

At the end of this phase we have proven:

- Slurm controller is operational.
- MUNGE authentication is operational.
- Compute node registration is operational.
- CPU topology is correctly registered.
- L40S is registered as Slurm GRES.
- GPU allocation through `srun --gres=gpu:L40S:1` works.
- `CUDA_VISIBLE_DEVICES` is set for GPU allocations.
- Jobs without a GPU request cannot access the L40S.
- cgroup v2 is active.
- `task/cgroup` is active.
- CPU cpuset enforcement works.
- Memory limits are applied at the step/user cgroup level.
- The Slurm job/step/task hierarchy is visible and understood.

This is the baseline for the next workload phase.

---

# 18. Deliberately NOT included

The following were support/workaround activities and are intentionally excluded from the architecture narrative:

- copying configuration files through the local Mac workstation
- temporary files used to transfer MUNGE or Slurm configuration
- SSH transfer mechanics
- temporary credential/file staging

They are not part of how the final Slurm architecture works.

---

# 19. Next phase boundary

Do not proceed directly to distributed training yet.

The next validation should exercise the current resource-control foundation with a **real GPU workload** and collect evidence for:

1. GPU utilization and HBM usage
2. CPU confinement during GPU work
3. memory enforcement under pressure
4. Slurm job/step lifecycle
5. GPU process visibility
6. workload cleanup after job termination

After that, the lab can move into the AI workload/storage layer.
