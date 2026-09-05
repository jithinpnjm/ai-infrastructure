# Lab 01 — Phase 01: Slurm Controller and Compute-Node Operating Model

## Purpose

This document explains **how the Slurm cluster is assembled and how the pieces communicate and become operational**. It is intentionally procedural and conceptual: the goal is to understand why each configuration exists, what lives on the controller versus the compute node, how a physical GPU becomes a schedulable Slurm resource, and how the controller continuously tracks node state.

Workstation transfer/copy commands and temporary file staging are deliberately excluded. They are implementation workarounds, not part of the Slurm architecture.

---

# 1. The mental model

Slurm has two fundamentally different roles in this lab:

```text
                         CLUSTER CONTROL PLANE

                 +-----------------------------+
                 | slurm-controller-01         |
                 |                             |
                 | slurmctld                   |
                 | MUNGE                       |
                 | slurm.conf                  |
                 | scheduler / resource view  |
                 +-------------+---------------+
                               |
                         Slurm RPC
                         + MUNGE auth
                               |
                               v
                 +-----------------------------+
                 | l40-node-01                 |
                 |                             |
                 | slurmd                      |
                 | slurmstepd                  |
                 | NVIDIA driver + CUDA        |
                 | L40S                        |
                 | gres.conf                   |
                 | cgroup.conf                 |
                 +-----------------------------+
                         COMPUTE PLANE
```

**Controller:** decides where work can run and maintains the cluster's scheduling state.

**Compute node:** actually runs the workload and enforces the allocation locally through `slurmd`, `slurmstepd`, Linux cgroups, and the GPU device stack.

The controller does not make `/dev/nvidia0` exist. The NVIDIA driver does that on the compute node. Slurm then maps that physical resource into a logical schedulable GRES.

---

# 2. Build order used in this lab

The dependency chain is important. The pieces were not configured in an arbitrary order.

```text
1. Create controller VM
        |
        v
2. Install Slurm controller + MUNGE
        |
        v
3. Define cluster identity / partition / node expectation
        |
        v
4. Create L40S compute VM
        |
        v
5. Install NVIDIA driver + CUDA on compute node
        |
        v
6. Verify physical GPU works independently of Slurm
        |
        v
7. Install Slurm node daemon + MUNGE
        |
        v
8. Configure gres.conf on compute node
        |
        v
9. Configure matching Gres=... in slurm.conf
        |
        v
10. Start slurmd and register node with slurmctld
        |
        v
11. Controller accepts node registration
        |
        v
12. Node becomes IDLE and schedulable
        |
        v
13. Enable task/cgroup + cgroup.conf
        |
        v
14. Submit real Slurm allocations with srun/sbatch
        |
        v
15. slurmd/slurmstepd create execution hierarchy
        |
        v
16. Linux cgroups enforce CPU/RAM/GPU restrictions
```

The key dependency is:

> **The GPU must first exist and work at the Linux/NVIDIA level. Slurm does not create the GPU; it schedules and controls access to it.**

---

# 3. Controller setup

## 3.1 Cluster identity

The controller contains:

```ini
ClusterName=ai-factory-lab
```

This identifies the Slurm cluster and is persisted by `slurmctld`.

It was initially changed after state initialization in this lab and caused:

```text
CLUSTER NAME MISMATCH
```

The cluster identity is now treated as fixed.

---

## 3.2 Controller daemon

The controller runs:

```text
slurmctld
```

Its job is to maintain the authoritative scheduling view:

- configured nodes
- node states
- partitions
- resource availability
- job allocations
- scheduling decisions
- job/step metadata

Validation:

```bash
systemctl is-active slurmctld
scontrol ping
```

Observed:

```text
active
Slurmctld(primary) at slurm-controller-01 is UP
```

---

# 4. What belongs in `slurm.conf`?

`slurm.conf` is the **cluster-wide Slurm configuration** consumed by Slurm daemons.

In this lab the important settings include:

```ini
ClusterName=ai-factory-lab
SlurmctldHost=slurm-controller-01
AuthType=auth/munge

GresTypes=gpu

SelectType=select/cons_tres
SelectTypeParameters=CR_CORE_MEMORY

TaskPlugin=task/cgroup
```

And the controller has a node definition:

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

The actual configuration in the lab is one logical line; the multiline form above is only for readability.

### Why the controller needs the `NodeName` definition

The controller must know **what it expects the node to be** before it can schedule work there.

It defines the node's:

- identity
- address
- CPU topology
- memory
- GRES resources
- initial administrative state

The node subsequently registers its actual capabilities through `slurmd`.

The controller therefore has both:

```text
configured expectation
        +
actual node registration
        =
current node state
```

---

# 5. Do all nodes need the same `slurm.conf`?

## Short answer

**Normally, yes: use one consistent cluster `slurm.conf` across the controller and all Slurm daemons.**

For this lab we intentionally used the same cluster configuration on the controller and L40 node.

However, understand the roles rather than thinking of it as simply "copy the file everywhere":

### Controller

`slurmctld` needs the cluster-wide configuration and all relevant node definitions because it schedules the entire cluster.

### Compute node

`slurmd` needs the cluster configuration so it knows:

- cluster identity
- controller location
- authentication settings
- its node identity
- resource configuration
- task/cgroup behavior

### Multi-node cluster

With nodes `l40-node-01`, `l40-node-02`, etc., the common cluster configuration can contain definitions for all nodes. Each `slurmd` reads the same cluster configuration but acts as the daemon for its own node.

A production deployment should maintain a **single source of truth** for `slurm.conf` rather than hand-maintaining divergent copies.

`gres.conf` and `cgroup.conf` are different: these are primarily **compute-node local configuration** because they describe local devices and local enforcement behavior.

---

# 6. How the physical GPU becomes a Slurm resource

This was one of the most important parts of the lab.

There are three layers:

```text
NVIDIA / Linux layer
        |
        | physical GPU
        v
/dev/nvidia0
        |
        | gres.conf
        v
Slurm GRES
 gpu:L40S
        |
        | slurm.conf NodeName Gres=
        v
Controller's resource model
        |
        | --gres=gpu:L40S:1
        v
Job allocation
```

## 6.1 NVIDIA layer

The NVIDIA driver exposes the GPU to Linux:

```bash
nvidia-smi -L
```

Observed:

```text
GPU 0: NVIDIA L40S (...)
```

Device nodes included:

```text
/dev/nvidia0
/dev/nvidiactl
/dev/nvidia-uvm
/dev/nvidia-modeset
```

This proves the GPU is functional independently of Slurm.

---

## 6.2 `gres.conf`

On the compute node:

```text
Name=gpu Type=L40S File=/dev/nvidia0
```

This tells Slurm's GRES layer:

> There is one GPU resource of type `L40S`, backed by `/dev/nvidia0`.

The critical matching string is:

```text
gpu:L40S
```

We previously hit a mismatch between the configured GRES type and NVIDIA's discovered GPU type. The working configuration is `L40S`.

Do **not** interpret `NVIDIA L40S` as a hierarchical Slurm resource name such as `NVIDIA:GPU:L40S`. Slurm's resource syntax here is `gpu:<type>`.

---

## 6.3 `slurmd -G`

On the compute node:

```bash
slurmd -G
```

Reported:

```text
Gres Name=gpu Type=L40S Count=1 Index=0 ID=... File=/dev/nvidia0
```

This is a crucial validation because it proves that the node-side Slurm GRES parser can discover and map the physical NVIDIA device.

---

## 6.4 `slurm.conf` GRES declaration

The controller's node definition contains:

```ini
Gres=gpu:L40S
```

Together:

```text
gres.conf
    gpu / L40S /dev/nvidia0
             |
             v
slurm.conf
    node has gpu:L40S
```

This connects **physical hardware discovery** to the **controller's schedulable resource model**.

---

# 7. How node registration works

The controller does not simply discover a VM by looking at the network.

The compute node runs:

```text
slurmd
```

When `slurmd` starts, it reads its Slurm configuration, discovers local resources, and communicates with `slurmctld`.

Conceptually:

```text
l40-node-01
    |
    | slurmd starts
    |
    | discovers:
    | - hostname
    | - CPUs
    | - memory
    | - topology
    | - GRES
    |
    | registration RPC
    v
slurmctld
    |
    | compares registration with
    | configured NodeName definition
    v
node state maintained by controller
```

The node does not need to manually execute a command on the controller to "update" its details.

**`slurmd` registration is the mechanism that updates the controller.**

---

# 8. Configured node vs registered node

This distinction explains many Slurm troubleshooting cases.

## Configured

The controller configuration says:

```text
l40-node-01
16 CPUs
96556 MB RAM
1 × gpu:L40S
```

This is the controller's expected resource model.

## Registered

`slurmd` reports what the node actually has and its daemon state.

If the values do not match sufficiently, Slurm can reject registration or put the node into a problematic state depending on the mismatch.

This is why we corrected the CPU topology to match:

```text
CPUs=16
SocketsPerBoard=1
CoresPerSocket=8
ThreadsPerCore=2
RealMemory=96556
```

Validation:

```bash
scontrol show node l40-node-01
```

Observed healthy values:

```text
CPUTot=16
RealMemory=96556
ThreadsPerCore=2
State=IDLE
```

---

# 9. How the node state continuously changes

`slurmctld` maintains a live state for every configured node.

The state is not a static value written once during setup.

`slurmd` periodically communicates with the controller through Slurm's node/daemon communication and registration mechanisms. The controller uses these communications, resource information, job allocation state, and administrative actions to maintain the node's current state.

Conceptually:

```text
                     slurmctld
                         |
             +-----------+-----------+
             |                       |
       configured node          node communications
             |                       |
             +-----------+-----------+
                         |
                         v
                  current node state
```

## Common lifecycle states

A simplified lifecycle is:

```text
UNKNOWN
   |
   | slurmd registers successfully
   v
IDLE
   |
   | job allocated
   v
ALLOCATED / MIXED
   |
   | job completes
   v
IDLE
```

Other states can occur because of failures or administration:

```text
DOWN
DRAIN
DRAINING
FAIL
```

The exact state combination can include flags, so always inspect the full state with:

```bash
scontrol show node l40-node-01
```

and summarize partitions with:

```bash
sinfo
```

---

# 10. What `IDLE` actually means

When we saw:

```text
sinfo

gpu* up infinite 1 idle l40-node-01
```

this did **not** merely mean "the VM is powered on".

It meant, at the Slurm level, that the node was:

- known to the controller
- registered/healthy
- assigned to the `gpu` partition
- currently not consuming its schedulable resources for a running allocation
- eligible for scheduling

That is a much stronger statement than successful SSH access.

---

# 11. What happens when a job is submitted

For:

```bash
srun -p gpu --gres=gpu:L40S:1 --cpus-per-task=4 --mem=4096M --pty bash
```

the flow is:

```text
User
 |
 | srun request
 v
slurmctld
 |
 | find suitable node
 | reserve resources
 v
l40-node-01
 |
 | slurmd receives launch request
 v
slurmstepd
 |
 | create step/task execution context
 | establish environment
 | establish cgroup hierarchy
 v
workload process
```

At this point two different things happen:

### Environment

Slurm exports job-specific information such as:

```text
SLURM_JOB_ID
SLURM_CPUS_ON_NODE
SLURM_MEM_PER_NODE
CUDA_VISIBLE_DEVICES
```

These variables describe the allocation and help applications use it correctly.

### Enforcement

`task/cgroup` and `cgroup.conf` enforce the allocation through Linux cgroup v2.

```text
Environment variables = information/configuration
cgroups                = enforcement
```

---

# 12. How cgroup enforcement fits into the node

The compute node has:

```text
Linux kernel
   |
   +-- cgroup v2: /sys/fs/cgroup
   |
   +-- NVIDIA driver
   |      |
   |      +-- /dev/nvidia0
   |
   +-- slurmd
          |
          +-- slurmstepd
```

With:

```ini
TaskPlugin=task/cgroup
```

Slurm places workload processes into a cgroup hierarchy.

An observed task had:

```text
0::/system.slice/l40-node-01_slurmstepd.scope/job_6/step_0/user/task_0
```

Conceptually:

```text
system.slice
  |
  +-- l40-node-01_slurmstepd.scope
        |
        +-- job_6
              |
              +-- step_0
                    |
                    +-- user
                          |
                          +-- task_0
```

The exact hierarchy is implementation/configuration dependent; the important model is:

```text
Job  = allocation
Step = execution unit inside allocation
Task = launched workload unit
```

---

# 13. How the requested resources become kernel controls

## CPU

Request:

```text
--cpus-per-task=4
```

Slurm allocation:

```text
4 CPUs
```

cgroup result:

```text
cpuset.cpus.effective = 0-3
```

Therefore the allocation was translated into actual CPU confinement.

---

## Memory

Request:

```text
--mem=4096M
```

The relevant parent cgroup showed:

```text
memory.max  = 4294967296
memory.high = 4294967296
```

which is 4096 MiB.

The task leaf itself showed `max`; this was not a failure because the limit was applied at the parent `step_0/user` level.

---

## GPU

Request:

```text
--gres=gpu:L40S:1
```

Slurm environment:

```text
CUDA_VISIBLE_DEVICES=0
```

GPU visible:

```text
nvidia-smi -L
GPU 0: NVIDIA L40S
```

Without a GPU request:

```text
CUDA_VISIBLE_DEVICES=
nvidia-smi -L
No devices found.
```

This proves that the allocation is enforced, not merely advertised through an environment variable.

---

# 14. Why `TaskPlugin` is configured on controller and node

The lab has:

```ini
TaskPlugin=task/cgroup
```

on both the controller and compute node configurations.

The important operational point is that **the actual cgroup creation and task placement happen on the compute node**, through `slurmd`/`slurmstepd`.

The controller must nevertheless consume a consistent Slurm configuration as part of the cluster control plane.

The compute node is where the local kernel resources are actually controlled.

---

# 15. Why `cgroup.conf` is different from `slurm.conf`

`slurm.conf` describes the cluster.

`cgroup.conf` describes cgroup resource-enforcement behavior on the node.

Current relevant node configuration:

```ini
CgroupMountpoint=/sys/fs/cgroup
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
AllowedSwapSpace=200
```

This is local enforcement configuration and belongs with the compute daemon.

The package-provided example also contained obsolete options for the installed Slurm version:

```text
CgroupAutomount
ConstrainKmemSpace
```

Those caused `slurmd` to fail parsing `cgroup.conf` and were removed.

Lesson:

> Always validate packaged examples against the exact installed Slurm version.

---

# 16. Why we did not add GPU to `AccountingStorageTRES`

An attempt was made to add:

```ini
AccountingStorageTRES=...,gres/gpu
```

This caused `slurmctld` to fail with a requirement for `slurmdbd`.

The setting was removed.

The important conceptual distinction is:

```text
GRES configuration
    -> GPU can be allocated to jobs

AccountingStorageTRES
    -> accounting/database tracking of resources
```

We do not need `slurmdbd` merely to make the current single-node GRES allocation work.

---

# 17. Node-state troubleshooting model

When a node does not become `IDLE`, troubleshoot in this order:

```text
1. Is the VM/network reachable?
       |
       v
2. Is munge active and trusted?
       |
       v
3. Is slurmd running?
       |
       v
4. Does slurmd read the same cluster configuration?
       |
       v
5. Does hostname/address match NodeName configuration?
       |
       v
6. Does CPU/memory topology match?
       |
       v
7. Does GRES match?
       |
       v
8. Does slurmd successfully register?
       |
       v
9. What does slurmctld report in scontrol show node?
```

Useful commands:

Controller:

```bash
scontrol ping
sinfo
scontrol show node l40-node-01
```

Node:

```bash
systemctl status slurmd --no-pager
journalctl -u slurmd -n 100 --no-pager
slurmd -G
```

Authentication:

```bash
systemctl is-active munge
munge -n | unmunge
```

---

# 18. What we have now proven

The complete chain is operational:

```text
Nebius VM
   |
   v
Ubuntu kernel
   |
   +-- NVIDIA driver
   |      |
   |      +-- L40S works
   |
   +-- Slurm + MUNGE
          |
          +-- slurmd
          |     |
          |     +-- GRES discovers L40S
          |     +-- registers with controller
          |
          +-- slurmctld
                |
                +-- knows node
                +-- knows GPU resource
                +-- schedules job
                |
                v
             slurmstepd
                |
                v
             cgroup v2
                |
                +-- CPU confinement
                +-- memory limit
                +-- GPU device isolation
                |
                v
             workload
```

The key principle for the rest of the AI factory lab is:

> **Hardware is discovered and made usable by the OS and vendor stack first. Slurm turns that hardware into a schedulable resource. The controller allocates it. The compute node enforces the allocation.**

---

# 19. Support activities intentionally excluded

Not part of the architecture or operating model:

- workstation-to-server file copies
- temporary files used to transfer MUNGE keys
- temporary credential staging
- SSH transfer mechanics

Those activities solved operational access problems during the lab but do not explain how the final Slurm cluster works.
