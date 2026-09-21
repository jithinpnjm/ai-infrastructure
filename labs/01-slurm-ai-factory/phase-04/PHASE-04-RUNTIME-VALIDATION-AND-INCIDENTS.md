# Phase 04 — Runtime Validation, Incident Log, and GPU Execution Proof

## Purpose

Phase 04 is the first runtime exercise of the Phase 03 Ansible worker configuration against real Nebius L40S GPU VMs.

This document is an **operational record**, not just a success checklist. It records:

- the exact runtime validation performed;
- commands used;
- what each command proves;
- failures encountered;
- the meaning of each failure;
- the troubleshooting path;
- what was conclusively fixed versus what remained unproven;
- the final successful Slurm/CUDA execution path;
- the state to preserve before shutting down the lab.

The goal is that a future engineer can reproduce the environment from the controller snapshot without relying on chat history.

---

# 1. Final validated architecture

The runtime path that was successfully demonstrated was:

```text
Nebius
  |
  +-- slurm-controller-01
  |      |
  |      +-- slurmctld
  |      +-- slurmdbd
  |      +-- MariaDB
  |      +-- MUNGE
  |
  +-- l40-node-01
  |      |
  |      +-- NVIDIA L40S
  |      +-- NVIDIA driver 580.173.02
  |      +-- CUDA 13.0
  |      +-- nvcc 13.0.88
  |      +-- MUNGE
  |      +-- slurmd
  |
  +-- l40-node-02
         |
         +-- NVIDIA L40S
         +-- NVIDIA driver 580.173.02
         +-- CUDA 13.0
         +-- nvcc 13.0.88
         +-- MUNGE
         +-- slurmd
```

Slurm scheduling path:

```text
srun --gres=gpu:1
        |
        v
slurmctld
        |
        v
partition=gpu
        |
        v
node selection
        |
        v
slurmd / slurmstepd
        |
        v
GRES gpu:L40S
        |
        v
/dev/nvidia0
        |
        v
CUDA application
        |
        v
NVIDIA L40S
```

---

# 2. Verified worker baseline

| Property | l40-node-01 | l40-node-02 |
|---|---|---|
| Private IP | 10.0.0.57 | 10.0.0.36 |
| GPU | NVIDIA L40S | NVIDIA L40S |
| GPU count | 1 | 1 |
| GPU memory | 46068 MiB | 46068 MiB |
| NVIDIA driver | 580.173.02 | 580.173.02 |
| CUDA | 13.0 | 13.0 |
| OS | Ubuntu 24.04 | Ubuntu 24.04 |
| Kernel | 6.11.0-1016-nvidia | 6.11.0-1016-nvidia |

The Nebius-generated hostnames were not used as the logical Slurm node names. The lab uses:

```text
l40-node-01
l40-node-02
```

This matters because cloud-generated hostnames can change independently of the cluster's logical node identity.

---

# 3. Ansible runtime convergence

The Phase 03 Ansible playbook was executed against both workers.

Command:

```bash
cd /tmp/ai-infrastructure/labs/01-slurm-ai-factory/phase-03/ansible

ansible-playbook -i inventories/lab/hosts.yml playbooks/gpu-node.yml
```

The successful convergence included:

- base configuration;
- hostname normalization;
- NVIDIA validation;
- MUNGE installation/configuration;
- Slurm worker packages;
- worker `slurm.conf`;
- `gres.conf`;
- cgroup configuration;
- `slurmd`;
- validation.

Successful final validation output:

```text
NVIDIA device: /dev/nvidia0 present
cgroup filesystem: cgroup2fs
MUNGE: active
slurmd: active
GRES: validated
```

The play recap showed both workers converged successfully.

A later rerun changed only the worker Slurm configuration after the controller IP changed, confirming that the playbook could converge an already-configured worker rather than requiring a fresh machine.

---

# 4. Issue: cloud hostname did not match Slurm node name

## Symptom

Initially, `slurmd -G` could not determine the expected NodeName because the Nebius-generated hostname differed from the logical Slurm node name.

The cloud VM had a generated hostname similar to:

```text
computeinstance-e00bb19dy3vzevy11a
```

while Slurm expected:

```text
l40-node-01
```

## Meaning

Slurm uses the node identity from its configuration when registering a compute daemon.

A cloud-generated hostname should not accidentally become the cluster's logical identity.

## Resolution

The Ansible `base` role was changed to set:

```text
hostname = inventory_hostname
```

The workers therefore became:

```text
l40-node-01
l40-node-02
```

This fix was committed as:

```text
0bbd50c57c85b41d3fd9ff27a9b7fb1d3412ab58
```

## Lesson

For cloud compute nodes:

```text
cloud instance identity
        !=
cluster logical node identity
```

The latter must be deterministic.

---

# 5. Issue: `slurmd -G` output appeared on stderr

## Symptom

The GRES validation task initially failed to see valid `slurmd -G` output.

Manual execution showed that useful output was emitted through stderr rather than stdout.

## Meaning

A command can return a successful result while placing diagnostic/validation output on stderr.

Automation that only captures stdout can therefore produce a false failure.

## Resolution

The validation role was changed to combine stdout and stderr before evaluating the `slurmd -G` result.

Commit:

```text
0280344a98d6ecfabab8f7de6609dc053d46bce1
```

## Lesson

When converting manual diagnostics into Ansible:

```text
command exit code
+
stdout
+
stderr
```

must all be considered.

---

# 6. Controller snapshot restore changed the controller IP

The controller was snapshot-restored/recreated.

Before the restore, the controller used:

```text
10.0.0.4
```

After restore/recreation, the controller used:

```text
10.0.0.0
```

The controller hostname initially became a Nebius-generated hostname. It was restored to the logical cluster identity with:

```bash
hostnamectl set-hostname slurm-controller-01
```

## Why this matters

Slurm workers had:

```text
SlurmctldHost=slurm-controller-01(10.0.0.4)
```

The restored controller was actually reachable at `10.0.0.0`.

A snapshot preserves disk state, but **network identity is a property of the newly attached VM/network interface and must be revalidated**.

## Resolution

The Ansible variable was updated:

```yaml
slurm_controller_addr: 10.0.0.0
```

The workers were then reconverged with Ansible.

Commit:

```text
2122d2ea36b63168cbae1c0769261362a02b3673
```

## Future rule

Never assume the controller IP survived a VM recreation.

Always verify:

```bash
hostname -f
ip -br addr
ip route
```

and then update the cluster configuration source of truth.

---

# 7. Issue: controller expected stale worker hardware

This was the most important Slurm registration failure.

## Symptom

The controller reported:

```text
State=DOWN+INVALID_REG
Reason=Low socket*core*thread count, Low CPUs,
       Low RealMemory
       (reported:32094 < 100.00% of configured:96556)
```

The controller's old node definition expected approximately:

```text
CPUs=16
RealMemory=96556
```

while the actual workers registered:

```text
CPUs=8
RealMemory=32094
```

## Meaning

Slurm compares the resources reported by `slurmd` against the configured minimum node resources.

If the node registers with less configured CPU/memory/topology, Slurm protects the cluster by refusing to place the node into service.

This is not a GPU failure.

It is a **controller node-definition versus worker hardware mismatch**.

## Correct troubleshooting method

Do not guess CPU topology.

On every new worker, run:

```bash
slurmd -C
```

This reports the actual hardware configuration in Slurm's node-definition format.

The controller's `NodeName` definition should then be based on that verified output.

Official Slurm documentation describes `slurmd -C` as reporting the actual hardware configuration and recommends matching node configuration to the worker's reported resources.

Reference:
https://slurm.schedmd.com/slurmd.html

## Resolution

The controller node definitions were corrected to match the actual registered worker configuration.

After reconfiguration, `l40-node-01` became:

```text
CPUTot=8
RealMemory=32094
ThreadsPerCore=1
State=IDLE
```

and ultimately both nodes reached:

```text
gpu* up infinite 2 idle l40-node-[01-02]
```

## Lesson

The controller configuration must not be based on:

- the GPU platform marketing specification;
- an old VM;
- a stale snapshot;
- guessed CPU topology.

Use:

```text
slurmd -C
```

as the worker-side hardware evidence.

---

# 8. Issue: MUNGE authentication errors

During registration troubleshooting, the controller logged errors similar to:

```text
Munge decode failed: Invalid credential
MESSAGE_NODE_REGISTRATION_STATUS has authentication error
Protocol authentication error
```

## Meaning

Slurm's authentication layer was rejecting an authenticated RPC.

MUNGE is the trust/authentication mechanism in this lab. A MUNGE failure therefore prevents otherwise healthy `slurmd` processes from successfully communicating with `slurmctld`.

This is independent of GPU functionality.

## Checks performed

Controller and worker MUNGE services were checked:

```bash
systemctl status munge --no-pager
```

Local encode/decode was tested:

```bash
munge -n | unmunge
```

The MUNGE key SHA-256 was checked on the controller and at least one worker:

```text
75dcd8df132f7be0f069906b2f504967f8eca65e834e953f7039011188d2748e
```

The key file permissions were also inspected.

## Important conclusion

The exact root cause of the transient MUNGE authentication error was **not conclusively isolated** from the available evidence.

The lab did not invent a key-mismatch explanation simply because MUNGE reported an authentication error.

The later `l40-node-02` VM also became temporarily unresponsive and was rebooted. After the reboot, both workers registered successfully.

Therefore the incident should be recorded as:

```text
MUNGE authentication failure observed
        |
        +-- local MUNGE validation succeeded
        +-- key hash checked
        +-- service restarted
        +-- exact transient cause not conclusively isolated
        |
        +-- l40-node-02 subsequently rebooted
        |
        v
cluster returned to healthy state
```

## Future diagnostic improvement

For a future recurrence, perform a true cross-node MUNGE test rather than relying only on local tests:

```bash
munge -n | ssh <worker> unmunge
```

or the equivalent test from the worker to the controller, using an appropriate authenticated administrative path.

Also compare:

```bash
sha256sum /etc/munge/munge.key
stat /etc/munge/munge.key
systemctl status munge
timedatectl
```

on every participant.

---

# 9. Issue: non-root `scontrol update`

During troubleshooting, an administrative `scontrol update` was attempted as a non-root user.

The controller logged:

```text
Security violation, UPDATE_NODE RPC from uid=1001
Invalid user id
```

## Meaning

Some Slurm administrative operations require an authorized Slurm administrator.

This error was **not** a worker hardware problem.

## Lesson

Separate:

```text
Slurm control-plane authorization
```

from:

```text
Slurm node registration
```

When performing node-state administration in this lab, use the configured Slurm administrator/root context.

---

# 10. Issue: l40-node-02 temporarily became unresponsive

## Symptom

The controller showed:

```text
l40-node-02 State=IDLE+NOT_RESPONDING
```

SSH to the node also became unavailable.

## Interpretation

This was no longer simply a Slurm configuration problem. The VM itself appeared unhealthy/unresponsive.

## Resolution

The VM was restarted through the cloud control plane.

After the reboot:

```text
gpu* up infinite 2 idle l40-node-[01-02]
```

Both nodes were healthy.

## Lesson

When a node simultaneously shows:

- Slurm `NOT_RESPONDING`;
- SSH unavailable;
- inability to inspect `slurmd`;
- inability to inspect `munge`;

investigate the **VM/OS layer** before continuing with Slurm configuration changes.

---

# 11. Final Slurm registration state

The final controller state was:

```text
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
gpu*         up   infinite      2   idle l40-node-[01-02]
```

For `l40-node-01`:

```text
CPUAlloc=0
CPUEfctv=8
CPUTot=8
RealMemory=32094
State=IDLE
ThreadsPerCore=1
```

For `l40-node-02`:

```text
CPUAlloc=0
CPUEfctv=8
CPUTot=8
RealMemory=32094
State=IDLE
ThreadsPerCore=1
```

This is the healthy scheduler state required before workload validation.

---

# 12. GPU allocation validation

The first end-to-end GPU scheduling test was:

```bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1   nvidia-smi
```

Successful output showed:

```text
NVIDIA-SMI 580.173.02
Driver Version: 580.173.02
CUDA Version: 13.0
GPU: NVIDIA L40S
Memory: 46068 MiB
```

Slurm accounting recorded:

```text
JobID  JobName     Partition  Account  AllocCPUS  State      ExitCode
10     nvidia-smi  gpu        root     1          COMPLETED  0:0
10.0   nvidia-smi             root     1          COMPLETED  0:0
```

## What this proves

It proves the complete basic scheduling/resource path:

```text
job request
  -> slurmctld
  -> GPU partition
  -> GRES allocation
  -> worker
  -> NVIDIA device
  -> command execution
  -> accounting record
```

It does not by itself prove that a CUDA kernel executes.

---

# 13. CUDA baseline validation

Inside a Slurm GPU allocation:

```bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1   bash -lc 'nvidia-smi -q | grep -E "CUDA Version|Product Name|Driver Version"'
```

Observed:

```text
Driver Version : 580.173.02
CUDA Version   : 13.0
Product Name   : NVIDIA L40S
```

Toolkit validation:

```bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1   bash -lc 'command -v nvcc || true; nvcc --version 2>/dev/null || true'
```

Observed:

```text
/usr/local/cuda-13.0/bin/nvcc

Cuda compilation tools, release 13.0, V13.0.88
```

## Important distinction

The lab explicitly validates these as separate layers:

```text
NVIDIA driver
    !=
CUDA runtime
    !=
CUDA Toolkit / nvcc
    !=
ML framework such as PyTorch
    !=
actual application workload
```

The preconfigured Nebius GPU image had the NVIDIA driver and CUDA toolkit, but did not have PyTorch installed.

---

# 14. Failed PyTorch validation

A Python CUDA workload was attempted:

```python
import torch
```

It failed with:

```text
ModuleNotFoundError: No module named 'torch'
```

## Meaning

This did **not** indicate a broken CUDA installation.

It indicated that the Python ML framework layer was not installed.

The correct architectural conclusion is:

```text
GPU infrastructure layer = validated
ML framework/application layer = not yet installed
```

The lab intentionally did not install PyTorch ad hoc on the worker after this failure.

That dependency belongs to the later **container/application/software-environment layer**.

---

# 15. Real CUDA kernel validation

To prove actual CUDA execution without installing PyTorch, a small CUDA C++ vector-add program was compiled with `nvcc` and executed through Slurm.

The important architecture is:

```text
controller
   |
   | srun
   v
GPU worker
   |
   +-- nvcc
   |
   +-- CUDA runtime
   |
   +-- L40S
   |
   v
CUDA kernel
```

The program performed:

```text
c[i] = a[i] + b[i]
```

with:

```text
a[i] = 1.0
b[i] = 2.0
```

The final successful output was:

```text
CUDA execution successful
c[0] = 3.0
c[N-1] = 3.0
```

## What this proves

This is stronger than `nvidia-smi`.

It proves:

1. Slurm successfully allocated a GPU.
2. The job ran on a GPU worker.
3. `nvcc` was available on that worker.
4. CUDA code compiled successfully.
5. The CUDA runtime initialized.
6. A real GPU kernel executed.
7. Device synchronization completed successfully.
8. The computed result was correct.

Therefore the fundamental:

```text
Slurm
  ->
GPU GRES
  ->
NVIDIA driver
  ->
CUDA toolkit/runtime
  ->
actual GPU kernel
```

path is validated.

---

# 16. Why the CUDA program was initially run incorrectly

The first compilation attempt was made on the controller.

The controller did not have `nvcc`, producing:

```text
Command 'nvcc' not found
```

This was expected from the architecture.

The controller is the **control plane**. The GPU workers contain the CUDA execution environment.

The corrected test created, compiled and executed the CUDA program inside the Slurm allocation:

```text
srun
  |
  v
GPU worker
  |
  +-- cat vector_add.cu
  +-- nvcc
  +-- ./vector_add
```

## Lesson

Do not install GPU/CUDA software on the controller merely to make a GPU workload test convenient.

The correct test should cross the scheduler boundary.

---

# 17. Final acceptance matrix

| Test | Result | Meaning |
|---|---|---|
| Ansible connectivity | PASS | Controller can reach workers |
| Base convergence | PASS | OS prerequisites converge |
| NVIDIA validation | PASS | L40S/driver baseline matches |
| MUNGE service | PASS | Local MUNGE service healthy |
| Slurm worker service | PASS | `slurmd` running |
| GRES validation | PASS | Slurm discovers L40S |
| cgroup v2 | PASS | Unified cgroup hierarchy present |
| Slurm registration | PASS | Both nodes registered |
| GPU `srun` | PASS | Scheduler allocates GPU |
| `nvidia-smi` in job | PASS | GPU visible in allocation |
| CUDA toolkit | PASS | `nvcc 13.0.88` available |
| CUDA kernel | PASS | Real GPU computation succeeds |
| PyTorch | NOT TESTED | Framework layer intentionally deferred |
| Multi-node NCCL | NOT TESTED | Future phase |
| InfiniBand / GPUDirect RDMA | NOT TESTED | Future phase |
| Kubernetes GPU scheduling | NOT TESTED | Future phase |

---

# 18. What must be preserved

Before shutting down the lab:

### Controller

Preserve the controller disk snapshot containing:

- Ubuntu/controller OS;
- Slurm installation;
- `slurmctld`;
- `slurmdbd`;
- MariaDB;
- Slurm accounting database;
- MUNGE configuration/key;
- Slurm state;
- controller configuration.

### Git

The repository remains the configuration source of truth for:

- Ansible;
- worker configuration;
- inventory model;
- expected GPU/driver;
- troubleshooting knowledge;
- recovery procedures.

### Secret

The MUNGE key must remain available to the Ansible controller out-of-band.

Never commit:

```text
/etc/munge/munge.key
```

or the Ansible copy:

```text
phase-03/ansible/secrets/munge.key
```

to Git.

---

# 19. Shutdown checkpoint

All expensive VMs can now be powered off.

The intended checkpoint is:

```text
Controller snapshot
      +
Git repository
      +
MUNGE secret
      +
documented worker configuration
      +
documented recovery procedure
```

No GPU VM needs to remain running.

The next session can start by creating a new controller VM from the saved controller snapshot.

---

# 20. Next-phase boundary

The next phase should **not** start by manually reconstructing Slurm from memory.

Start from the snapshot recovery procedure in:

```text
phase-04/CONTROLLER-SNAPSHOT-RECOVERY.md
```

Then:

1. boot the controller from the snapshot;
2. verify hostname and network identity;
3. verify Slurm/MUNGE/slurmdbd/MariaDB;
4. verify accounting data;
5. verify the controller's current IP;
6. update the Ansible controller address;
7. create fresh GPU workers;
8. discover their actual hardware with `slurmd -C`;
9. update inventory with their new private IPs;
10. run Ansible;
11. validate registration;
12. run one real GPU/CUDA test;
13. immediately shut down/destroy expensive resources when the phase does not require them.

---

# 21. Study points from this runtime phase

The engineer should be able to explain:

- Why Slurm needs a controller and `slurmd`.
- Why MUNGE errors prevent Slurm RPCs.
- Why a stale `RealMemory` value can put a healthy node into `INVALID_REG`.
- Why `slurmd -C` is preferable to guessing hardware topology.
- Why cloud hostnames should not automatically become cluster identities.
- Why `NodeAddr` and `SlurmctldHost` must follow actual network identity.
- Why `srun --gres=gpu:1` is stronger evidence than simply running `nvidia-smi`.
- The difference between NVIDIA driver, CUDA runtime, CUDA Toolkit, and PyTorch.
- Why the CUDA compiler belongs on compute workers rather than the controller.
- Why a successful CUDA kernel is stronger evidence than device enumeration.
- Why a VM-level failure must be separated from a Slurm-level failure.
- Why controller configuration and worker-reported hardware must agree.
- Why transient failures should be documented as unresolved when the evidence does not prove a root cause.

---

# 22. Source-of-truth rule

For future phases:

> **Every operational discovery becomes documentation before the infrastructure is destroyed.**

A failure is valuable only if the repository records:

```text
symptom
  ->
meaning
  ->
evidence
  ->
diagnostic commands
  ->
root cause (if proven)
  ->
remediation
  ->
validation
  ->
rebuild implication
```

Do not convert an observed symptom into an assumed root cause.

This is the standard for all subsequent AI-factory phases.


---

# Detailed Learning Appendix — Exact Runtime Troubleshooting Record

> This appendix is intentionally verbose. It records the actual commands and observations from the runtime session so the phase can be studied later, not merely remembered as "the cluster worked".

## A. Starting point

The two workers were:

| Node | IP | GPU |
|---|---|---|
| l40-node-01 | 10.0.0.57 | NVIDIA L40S |
| l40-node-02 | 10.0.0.36 | NVIDIA L40S |

The verified GPU baseline was:

~~~
Driver: 580.173.02
CUDA:   13.0
Memory: 46068 MiB
Kernel: 6.11.0-1016-nvidia
OS: Ubuntu 24.04
~~~

The workers were intentionally managed through Ansible rather than being configured manually.

The controller logical name was:

~~~
slurm-controller-01
~~~

---

## B. Ansible convergence — what we were actually proving

The playbook was executed from:

~~~
/tmp/ai-infrastructure/labs/01-slurm-ai-factory/phase-03/ansible
~~~

Command:

~~~bash
ansible-playbook -i inventories/lab/hosts.yml playbooks/gpu-node.yml
~~~

The playbook was structured as:

~~~
base
  ↓
nvidia
  ↓
munge
  ↓
slurm
  ↓
validation
~~~

The final worker validation printed:

~~~
NVIDIA device: /dev/nvidia0 present
cgroup filesystem: cgroup2fs
MUNGE: active
slurmd: active
GRES: validated
~~~

### Important learning point

This result only proves that the **worker-side configuration converged and its local checks passed**.

It does not yet prove:

~~~
slurmd
  ↓
network
  ↓
MUNGE
  ↓
slurmctld
  ↓
node registration
~~~

That had to be tested separately.

---

## C. Hostname problem — exact reasoning

The Nebius VM had a generated hostname rather than the intended logical name.

The intended Slurm identity was:

~~~
l40-node-01
~~~

The generated cloud identity looked like:

~~~
computeinstance-e00bb19dy3vzevy11a
~~~

The failure surfaced while working with:

~~~bash
slurmd -G
~~~

### Why this matters

Slurm has a node identity model. The controller configuration says which node it expects, while slurmd reports who it is.

If the OS hostname and Slurm configuration disagree, diagnostics such as GRES discovery and registration can become confusing.

### What we changed

The Ansible base role was changed to derive the OS hostname from the inventory hostname.

Result:

~~~
l40-node-01
l40-node-02
~~~

Commit:

~~~
0bbd50c57c85b41d3fd9ff27a9b7fb1d3412ab58
~~~

### Learning

Do not use a cloud-generated hostname as an implicit cluster identity.

Keep:

~~~
cloud VM identity
        ↓
replaceable

Slurm logical identity
        ↓
stable
~~~

---

## D. GRES validation problem — stdout versus stderr

The next problem was in the Ansible validation logic.

Manual execution of:

~~~bash
slurmd -G
~~~

showed valid information, but the Ansible validation did not see it because useful output was emitted on stderr.

### Why this is a real automation problem

A shell command has at least three useful signals:

~~~text
exit status
stdout
stderr
~~~

A validation task that checks only stdout can produce:

~~~text
command succeeded
+
stdout empty
=
false failure
~~~

### Fix

The validation role was changed to combine stdout and stderr before matching the expected GRES output.

Commit:

~~~
0280344a98d6ecfabab8f7de6609dc053d46bce1
~~~

### Learning

When turning manual infrastructure diagnostics into Ansible, always inspect how the command actually emits evidence.

Do not assume that "diagnostic output" means stdout.

---

## E. Controller snapshot recovery — network identity changed

The controller was snapshot-restored/recreated.

Before the restore:

~~~text
10.0.0.4
~~~

After the restore:

~~~text
10.0.0.0
~~~

The logical hostname also had to be restored:

~~~bash
hostnamectl set-hostname slurm-controller-01
~~~

### Why this mattered

The workers still had configuration referring to:

~~~text
SlurmctldHost=slurm-controller-01(10.0.0.4)
~~~

The real controller was now at:

~~~text
10.0.0.0
~~~

Therefore the worker configuration was stale.

### Correct recovery principle

A disk snapshot contains disk state.

A newly created VM can have a different:

- private IP;
- hostname;
- network interface identity.

Therefore after snapshot recovery always run:

~~~bash
hostname -f
ip -br addr
ip route
~~~

before assuming the old configuration is still valid.

### Fix

The Git-managed variable was changed to:

~~~yaml
slurm_controller_addr: 10.0.0.0
~~~

Commit:

~~~
2122d2ea36b63168cbae1c0769261362a02b3673
~~~

Then the worker playbook was rerun.

---

## F. Registration failure — INVALID_REG

After the controller-address correction, the scheduler still did not accept the workers.

The controller showed:

~~~text
State=DOWN+INVALID_REG
~~~

with:

~~~text
Reason=Low socket*core*thread count, Low CPUs,
Low RealMemory (reported:32094 < 100.00% of configured:96556)
~~~

### The critical numbers

The controller's stale definition expected approximately:

~~~text
CPUs=16
RealMemory=96556
~~~

The worker registered with:

~~~text
CPUs=8
RealMemory=32094
~~~

### What this means

This is a **resource-contract mismatch**.

The controller says:

~~~text
"This node must provide at least this much capacity."
~~~

The worker says:

~~~text
"I actually have this much capacity."
~~~

When the worker is below the configured requirement, Slurm rejects the registration rather than silently scheduling against incorrect capacity.

### What this is NOT

It is not evidence that:

- the NVIDIA GPU is broken;
- the driver is broken;
- CUDA is broken;
- GRES is necessarily broken.

It is specifically a node topology/resource configuration problem.

---

## G. The correct way to determine worker topology

The important command is:

~~~bash
slurmd -C
~~~

This should be run on the worker.

It is better evidence than copying CPU and memory numbers from:

- an old VM;
- a cloud product specification;
- a previous controller;
- memory;
- assumptions about hyperthreading.

### Why this matters

The controller needs the hardware model **as Slurm sees it**, not merely the advertised cloud instance model.

The correct troubleshooting loop is:

~~~text
worker
  ↓
slurmd -C
  ↓
actual Slurm topology
  ↓
controller NodeName
  ↓
scontrol reconfigure
  ↓
registration
~~~

After correcting the stale values, l40-node-01 became:

~~~text
CPUAlloc=0 CPUEfctv=8 CPUTot=8 CPULoad=0.02
RealMemory=32094 AllocMem=0 FreeMem=29832 Sockets=1 Boards=1
State=IDLE ThreadsPerCore=1 TmpDisk=0 Weight=1 Owner=N/A MCS_label=N/A
~~~

This is the evidence that the controller and worker resource models were aligned for that node.

---

## H. MUNGE authentication failure

During the registration troubleshooting, controller logs contained:

~~~text
Munge decode failed: Invalid credential
MESSAGE_NODE_REGISTRATION_STATUS has authentication error
Protocol authentication error
~~~

### What layer failed?

The important architecture is:

~~~text
slurmctld
    ↓
authenticated Slurm RPC
    ↓
MUNGE
    ↓
slurmd
~~~

Therefore an MUNGE credential failure is a **control-plane authentication problem**.

It is not evidence of a GPU failure.

### Commands actually used

Service status:

~~~bash
systemctl status munge --no-pager
~~~

Local encode/decode:

~~~bash
munge -n | unmunge
~~~

Key hash:

~~~bash
sha256sum /etc/munge/munge.key
~~~

Observed hash evidence:

~~~text
75dcd8df132f7be0f069906b2f504967f8eca65e834e953f7039011188d2748e
~~~

The key file permissions were also inspected.

MUNGE and slurmd were restarted during troubleshooting.

### What was proven?

Local MUNGE worked.

The key hash was checked.

The services were active.

### What was NOT proven?

The exact transient cause of the cross-node authentication failure was not conclusively isolated.

That distinction must remain in the documentation.

We should not write:

~~~text
"The MUNGE key was wrong."
~~~

because the evidence did not establish that.

### Better future diagnostic

A future recurrence should include a cross-node test such as:

~~~bash
munge -n | ssh <worker> unmunge
~~~

along with:

~~~bash
sha256sum /etc/munge/munge.key
stat /etc/munge/munge.key
systemctl status munge
timedatectl
~~~

on both sides.

---

## I. Administrative authorization error

During troubleshooting an administrative node update was run as a non-root user.

The controller logged:

~~~text
Security violation, UPDATE_NODE RPC from uid=1001
_slurm_rpc_update_node ... Invalid user id
~~~

### Meaning

This means the caller did not have the authorization required for that administrative operation.

It does not mean the worker failed registration.

It does not mean MUNGE is broken.

It is a separate control-plane authorization issue.

### Learning

When debugging Slurm, classify the failure:

~~~text
authentication
authorization
registration
scheduling
resource configuration
VM health
~~~

before changing configuration.

---

## J. l40-node-02 became unresponsive

The controller later showed:

~~~text
State=IDLE+NOT_RESPONDING
~~~

for l40-node-02.

At the same time, SSH access to the node was unavailable.

### Why this changed the diagnosis

At this point it was no longer useful to keep changing Slurm configuration blindly.

The diagnostic path became:

~~~text
Slurm says NOT_RESPONDING
        ↓
Can we reach port 6818?
        ↓
Can we SSH?
        ↓
Is the VM healthy?
~~~

The VM was restarted through the cloud control plane.

After the restart:

~~~text
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
gpu*         up   infinite      2   idle l40-node-[01-02]
~~~

### Learning

A scheduler state is not necessarily the root cause.

If SSH is also unavailable, investigate the VM/OS/network layer.

---

## K. Final scheduler state

The final healthy state was:

~~~text
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
gpu*         up   infinite      2   idle l40-node-[01-02]
~~~

This was the first clean indication that both GPU workers were available to the scheduler.

Only after this point did we proceed to GPU workload testing.

---

## L. GPU allocation — first scheduler-level proof

Command actually executed:

~~~bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1 \
  nvidia-smi
~~~

Output identified:

~~~text
NVIDIA-SMI 580.173.02
Driver Version: 580.173.02
CUDA Version: 13.0
GPU: NVIDIA L40S
46068 MiB
~~~

### What this proves

The command crossed the scheduler boundary:

~~~text
controller
   ↓
srun
   ↓
slurmctld
   ↓
gpu partition
   ↓
GRES request
   ↓
worker
   ↓
NVIDIA GPU
~~~

This is stronger than running nvidia-smi directly on the worker.

---

## M. Accounting proof

After the GPU job:

~~~bash
sacct
~~~

returned:

~~~text
JobID           JobName  Partition    Account  AllocCPUS      State ExitCode
------------ ---------- ---------- ---------- ---------- ---------- --------
10           nvidia-smi        gpu       root          1  COMPLETED      0:0
10.0         nvidia-smi                  root          1  COMPLETED      0:0
~~~

This showed that the completed GPU job was recorded by Slurm accounting.

---

## N. CUDA runtime and toolkit proof

Runtime query:

~~~bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1 \
  bash -lc 'nvidia-smi -q | grep -E "CUDA Version|Product Name|Driver Version"'
~~~

Observed:

~~~text
Driver Version : 580.173.02
CUDA Version   : 13.0
Product Name   : NVIDIA L40S
~~~

Toolkit query:

~~~bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1 \
  bash -lc 'command -v nvcc || true; nvcc --version 2>/dev/null || true'
~~~

Observed:

~~~text
/usr/local/cuda-13.0/bin/nvcc

Cuda compilation tools, release 13.0, V13.0.88
~~~

### Learning

The stack has multiple layers:

~~~text
NVIDIA driver
    ↓
CUDA runtime
    ↓
CUDA Toolkit / nvcc
    ↓
ML framework
    ↓
application
~~~

A failure in one layer must not automatically be attributed to another.

---

## O. PyTorch failure — what it actually told us

A Python CUDA workload was attempted.

The first important operation was:

~~~python
import torch
~~~

The result:

~~~text
ModuleNotFoundError: No module named 'torch'
~~~

### Correct interpretation

This proves only:

~~~text
PyTorch is not installed.
~~~

It does not prove:

~~~text
CUDA is broken.
~~~

By this point we had already independently proven the driver, CUDA version, and nvcc.

Therefore PyTorch installation was intentionally deferred rather than added ad hoc to the infrastructure layer.

---

## P. First CUDA compilation attempt — controller was the wrong place

The first attempt to compile the CUDA test was made on the controller.

The command:

~~~bash
nvcc -O2 /tmp/vector_add.cu -o /tmp/vector_add
~~~

returned:

~~~text
Command 'nvcc' not found, but can be installed with:
apt install nvidia-cuda-toolkit
~~~

### Why this is an important learning failure

The controller is not the GPU compute environment.

The intended architecture is:

~~~text
controller
   |
   | srun
   ↓
GPU worker
   |
   +-- nvcc
   +-- CUDA runtime
   +-- L40S
~~~

Installing CUDA on the controller merely to compile the test would weaken the architectural lesson.

The corrected test was therefore performed inside the Slurm allocation.

---

## Q. Actual CUDA kernel execution

The final test compiled and ran a CUDA vector-add program through Slurm.

The operation was:

~~~text
a[i] = 1.0
b[i] = 2.0
c[i] = a[i] + b[i]
~~~

The final output was:

~~~text
CUDA execution successful
c[0] = 3.0
c[N-1] = 3.0
~~~

### Why this is the strongest proof in this phase

The successful result means all of these layers worked together:

~~~text
Slurm allocation
    ↓
GPU worker
    ↓
nvcc
    ↓
CUDA runtime
    ↓
L40S
    ↓
kernel launch
    ↓
device synchronization
    ↓
correct result
~~~

This is actual GPU computation.

It is substantially stronger evidence than:

~~~bash
nvidia-smi
~~~

alone.

---

# R. Complete troubleshooting timeline

The practical sequence was:

~~~text
1. Create/use two L40S workers
        ↓
2. Run Ansible
        ↓
3. Hostname mismatch discovered
        ↓
4. Fix hostname via Ansible
        ↓
5. GRES validation output issue discovered
        ↓
6. Capture stderr as well as stdout
        ↓
7. Ansible converges successfully
        ↓
8. Controller snapshot/recreation changes controller IP
        ↓
9. Restore logical controller hostname
        ↓
10. Update controller address in Git
        ↓
11. Worker registration attempted
        ↓
12. INVALID_REG discovered
        ↓
13. Compare controller resources with worker resources
        ↓
14. Discover stale CPUs/memory configuration
        ↓
15. Correct controller node definitions
        ↓
16. MUNGE authentication errors observed
        ↓
17. Check service, local MUNGE, key hash, permissions
        ↓
18. Exact transient MUNGE cause remains unproven
        ↓
19. l40-node-02 becomes unresponsive
        ↓
20. VM restarted
        ↓
21. Both nodes become IDLE
        ↓
22. srun --gres=gpu:1 nvidia-smi succeeds
        ↓
23. sacct records GPU job
        ↓
24. CUDA 13 / nvcc 13.0.88 verified
        ↓
25. PyTorch test shows torch is not installed
        ↓
26. First nvcc attempt on controller fails
        ↓
27. CUDA test moved inside Slurm allocation
        ↓
28. Real CUDA vector-add kernel succeeds
~~~

This sequence is the actual learning path of the phase.

---

# S. Failure classification learned from the phase

A useful way to troubleshoot the factory is to move from lower layers to higher layers.

~~~text
Layer 1 — VM
    Is the VM alive?
    Can SSH connect?

Layer 2 — network
    Can the controller reach worker port 6818?

Layer 3 — authentication
    Is MUNGE working?

Layer 4 — worker daemon
    Is slurmd active?

Layer 5 — GPU discovery
    Does slurmd -G find the GPU?

Layer 6 — controller registration
    Does sinfo show the node?

Layer 7 — resource contract
    Does controller configuration match slurmd -C?

Layer 8 — scheduling
    Does srun allocate the GPU?

Layer 9 — GPU visibility
    Does nvidia-smi work inside the job?

Layer 10 — CUDA
    Can nvcc compile and can a kernel execute?

Layer 11 — ML framework
    Does PyTorch/vLLM/etc. work?

Layer 12 — distributed AI
    NCCL / InfiniBand / GPUDirect RDMA / multi-node training
~~~

The key operational lesson is:

> Do not troubleshoot layer 11 when layer 7 is broken.

---

# T. What we intentionally did not change

Several tempting changes were deliberately avoided.

### We did not install PyTorch

Reason:

~~~text
GPU infrastructure already proven.
PyTorch belongs to a later software/application layer.
~~~

### We did not install CUDA on the controller

Reason:

~~~text
CUDA belongs on GPU workers.
The correct test is through Slurm.
~~~

### We did not invent a MUNGE root cause

Reason:

~~~text
The available evidence did not prove the exact transient cause.
~~~

### We did not leave GPU VMs running

Reason:

~~~text
The infrastructure validation is complete for this phase.
GPU compute is expensive.
The controller snapshot is sufficient for recovery.
~~~

---

# U. What is proven versus what is still a future experiment

## Proven

~~~text
Two L40S workers can participate in the Slurm cluster.
MUNGE can operate locally.
GRES discovers the L40S.
Slurm can register the workers.
Slurm can allocate one GPU.
nvidia-smi works inside the allocation.
Slurm accounting records the GPU job.
CUDA 13.0 is available.
nvcc 13.0.88 is available.
A real CUDA kernel executes successfully.
~~~

## Not proven

~~~text
PyTorch
vLLM
containers / Pyxis / Enroot
multi-GPU
NCCL
InfiniBand
GPUDirect RDMA
distributed training
Kubernetes GPU scheduling
DRA
Run:ai
GPU Operator
high-availability Slurm controller
automated Nebius node lifecycle
~~~

These are deliberately left for later phases.

---

# V. Documentation and rebuild principle

The lab is being built as a progressive learning system.

Every important incident should be captured as:

~~~text
Observed symptom
      ↓
Exact command/output
      ↓
What that output means
      ↓
Possible causes
      ↓
Tests performed
      ↓
Proven root cause
      ↓
Fix
      ↓
Validation
      ↓
How to reproduce/rebuild
~~~

If the evidence does not prove the root cause, the documentation must say so.

This is more valuable than a clean-looking success report because it teaches the troubleshooting method required for a real AI infrastructure platform.

---

# W. End-of-day state

The validated cluster state before shutdown was:

~~~text
gpu* up infinite 2 idle l40-node-[01-02]
~~~

The GPU execution proof was:

~~~text
CUDA execution successful
c[0] = 3.0
c[N-1] = 3.0
~~~

The intended cost-control state after shutdown is:

~~~text
GPU workers: OFF
Controller VM: OFF
Controller disk snapshot: RETAINED
Git repository: RETAINED
MUNGE key: RETAINED SECURELY
~~~

Tomorrow's work should begin from the controller snapshot recovery runbook, not from an assumption that the old VM network identity still exists.
