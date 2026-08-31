# Lab 01 — Phase 01: Foundation Provisioning & Host Baseline

## Phase status

**Planning complete. Execution is manual.**

GitHub Actions is intentionally **not** introduced yet. We will execute Phase 01 manually, record the actual commands/results/failures, and automate the validated workflow at the end of the phase.

## Objective

Build and validate the production-shaped foundation on Nebius `eu-north1` without installing Slurm yet.

Phase 01 establishes the hosts, network identity, storage connectivity and operating-system baseline that later Slurm, GPU, container and distributed-training phases depend on.

The phase must finish with a reproducible host baseline and evidence that expensive GPU resources can be created, validated and destroyed safely.

## Target topology

```text
Nebius project-01 / eu-north1
│
├── Existing VPC: jithin-ai-infra-vpc-01
│   └── Existing subnet: jithin-ai-infra-subnet-01
│
├── Management host
│   └── slurm-controller
│       └── CPU-only VM
│
├── GPU development host
│   └── gpu-compute-01
│       └── L40S / preemptible
│
├── GPU factory hosts (created only for relevant experiments)
│   ├── gpu-compute-01
│   │   └── 8×H100 where available
│   └── gpu-compute-02
│       └── 8×H100 where available
│       └── InfiniBand / RDMA fabric
│
├── Nebius shared filesystem
│   └── /ai-factory
│
└── Nebius Object Storage
    └── ai-factory artifacts/datasets/checkpoints
```

The exact GPU-cluster resource shape is selected from the capability/quota discovery before provisioning; do not hard-code a SKU that has not been verified in the project.

## Phase sequence

### P01.1 — Nebius capability and quota discovery

Before spending money:

- confirm region/project
- inspect GPU quotas
- inspect available L40S and H100/H200 configurations
- inspect GPU Cluster / InfiniBand options
- inspect shared filesystem options
- inspect VM/storage quotas
- inspect preemptible availability
- record pricing assumptions and date

**Gate:** the selected topology is actually provisionable.

### P01.2 — Network foundation inspection

Validate the existing VPC/subnet and establish the management addressing model.

Inspect:

- CIDR
- routing
- DNS
- security groups
- ingress/egress rules
- internal reachability

**Gate:** controller and compute hosts can communicate on required management ports.

### P01.3 — Controller VM

Create a small CPU-only VM for:

- administration
- future `slurmctld`
- future `slurmdbd`
- Munge
- monitoring/control tools
- Ansible controller execution

Do not install Slurm yet.

**Gate:** stable SSH, hostname, time sync, DNS and package management.

### P01.4 — GPU development VM

Create the inexpensive/preemptible L40S host.

Initially treat it as a **plain Linux GPU server**. Do not use a prebuilt AI image if doing so hides the installation concepts we need to learn.

Inspect before software installation:

```text
uname -a
cat /etc/os-release
lscpu
lsblk
free -h
lspci -nn
lspci -nn | grep -Ei 'nvidia|3d|vga'
numactl --hardware
numastat
ip -br addr
ip -br link
ip route
```

At this point `lspci` should see the PCIe GPU, while `nvidia-smi` is expected to fail until the driver is installed.

### P01.5 — GPU factory capability host

When the H100/IB experiment is required, create the Nebius GPU Cluster in the selected configuration.

Immediately capture:

```text
nvidia-smi
nvidia-smi -L
nvidia-smi topo -m
lspci -tv
lscpu
numactl --hardware
numastat -p 1
ip -br addr
rdma link
ibstat
ibdev2netdev
```

This is where we establish the actual PCIe → NUMA → GPU → NIC topology before configuring NCCL.

### P01.6 — Shared filesystem

Provision Nebius-native shared storage.

Mount it consistently on controller and compute hosts using the Nebius-supported mechanism.

Create:

```text
/ai-factory/models
/ai-factory/datasets
/ai-factory/checkpoints
/ai-factory/jobs
/ai-factory/shared
```

Do not use an ad-hoc NFS VM as the primary design.

**Gate:** read/write from all participating hosts and persistence across GPU-node recreation.

### P01.7 — Object Storage

Create the durable artifact bucket and validate upload/download.

Initial layout:

```text
models/
datasets/
checkpoints/
training-results/
logs/
```

**Gate:** credentials are injected securely and no secret is committed to Git.

### P01.8 — Host baseline

Apply the minimum production baseline to controller and compute hosts:

- hostname
- `/etc/hosts` only where required
- DNS
- NTP/chrony/system time
- package repositories
- SSH hardening appropriate for the lab
- persistent journaling
- useful diagnostics
- `sysstat`
- `iostat`
- `ethtool`
- `pciutils`
- `numactl`
- `hwloc`
- `rdma-core` on IB hosts
- `ibutils`/vendor tools where available
- `iperf3`
- `fio`
- `jq`
- `curl`
- `git`

Do not tune kernel parameters speculatively. Every performance tuning change must have a measurable reason and rollback path.

### P01.9 — Observability baseline

Before workload testing, capture a baseline for:

- CPU
- memory
- NUMA
- PCIe
- network
- disk
- GPU
- GPU clocks
- HBM
- temperature/power
- RDMA devices

Useful commands:

```text
uptime
vmstat 1 5
iostat -xz 1 5
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
nvidia-smi
nvidia-smi dmon -s pucvmet
```

DCGM will be introduced in the GPU software phase, not hidden inside Phase 01.

### P01.10 — Failure and lifecycle tests

Before finalization, test at minimum:

1. Stop/restart the management network path and verify expected impact.
2. Reboot a compute host and verify persistent storage returns.
3. Destroy/recreate the disposable GPU VM and verify shared data survives.
4. Simulate storage unavailability and verify applications fail visibly rather than silently corrupting state.
5. Verify time synchronization after reboot.
6. Verify DNS and host identity after recreation.

Do not inject hardware-level GPU XID or physical InfiniBand failures in Phase 01. Those belong in the GPU/NCCL/network failure phases where recovery procedures are defined.

## Required evidence

Create `RESULTS.md` and record:

- actual Nebius resource IDs
- VM sizes
- GPU model
- region
- network CIDRs
- shared filesystem identifier
- object storage bucket name
- quota results
- baseline command outputs or summarized values
- installation deviations
- failures and corrections
- timestamps
- cost observations

Never commit secrets, private keys or tokens.

## Final Phase 01 gate

Phase 01 is complete only when:

- [ ] Nebius capability/quota discovery is recorded.
- [ ] Existing VPC/subnet validated.
- [ ] Controller host operational.
- [ ] L40S development host operational.
- [ ] H100/InfiniBand topology, if available, validated when provisioned.
- [ ] Shared filesystem mounted and persistent.
- [ ] Object Storage read/write validated.
- [ ] Hostnames/DNS/time synchronization validated.
- [ ] Diagnostic tooling installed.
- [ ] CPU/memory/storage/network/GPU baseline captured.
- [ ] GPU host can be safely destroyed and recreated without losing shared data.
- [ ] No unexplained baseline errors remain.
- [ ] Failure/lifecycle drills completed.
- [ ] `RESULTS.md` updated.
- [ ] Manual procedure is stable enough to automate.

## Automation deliverable at phase end

Only after the manual implementation is successful, add one Lab 01 GitHub Actions workflow with a controlled operation selector such as:

```text
validate-foundation
provision-controller
provision-dev-gpu
provision-h100-factory
provision-storage
validate
collect-evidence
destroy-expensive-compute
```

The workflow must default to safe/read-only operations and require an explicit destroy/provision choice. It should reuse Terraform/Ansible rather than contain long inline shell configuration.

## Next phase

**Phase 02 — Operating-system + NVIDIA GPU software foundation**

Phase 02 will deliberately install and validate the NVIDIA driver, CUDA toolkit/runtime, NVIDIA Container Toolkit and GPU diagnostics on the plain GPU host before Slurm is introduced.
