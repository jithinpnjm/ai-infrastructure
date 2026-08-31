# Lab 01 — Phase 00: AI Factory Architecture & Readiness

## 1. Purpose

Phase 00 defines the infrastructure contract for the complete Slurm AI Factory lab. It is a design and readiness gate, not an installation phase.

The design must be validated against the current Nebius services and GPU-cluster capabilities before expensive GPU infrastructure is provisioned.

## 2. Design principles

1. Production fidelity is more important than minimizing absolute spend.
2. Optimize cost per learning outcome.
3. Keep cheap persistent infrastructure available overnight.
4. Make expensive GPU/RDMA compute disposable and recreate it on demand.
5. Use Nebius-native services instead of building low-value replacements on VMs.
6. Build manually first; automate only after the manual implementation is known-good.
7. Use real model training and inference workloads later; toy `nvidia-smi` checks are only infrastructure health gates.
8. Record actual execution results, failures, corrections and performance baselines in the repository.

## 3. Target architecture

```text
                         NEBIUS PROJECT
                              |
                 +------------+-------------+
                 |                          |
              IAM / SA                    VPC
                 |                          |
                 |                    Management subnet
                 |                          |
                 |              +-----------+-----------+
                 |              |                       |
                 |        Slurm Controller         GPU management
                 |        CPU-only VM               interfaces
                 |              |                       |
                 |        slurmctld/slurmdbd             |
                 |        MariaDB + monitoring            |
                 |                                      |
                 +--------------------------------------+
                                |
                         Shared Filesystem
                                |
                    models / datasets / checkpoints
                                |
                         Object Storage
                                |
                     datasets / artifacts / archive

              GPU DATA PLANE (only when required)

                    Nebius GPU Cluster
                           |
                  InfiniBand fabric
                    /             \
             GPU node 01       GPU node 02
             8 x H100          8 x H100
                  \               /
                   +--- NCCL ----+
                        RDMA
                   GPUDirect RDMA
```

The management/data-plane separation is intentional:

- VPC/Ethernet: SSH, Slurm control traffic, administration, monitoring and service access.
- InfiniBand GPU fabric: NCCL/RDMA/distributed-training traffic when the selected Nebius GPU cluster provides it.
- Shared filesystem: POSIX model, dataset and checkpoint access.
- Object Storage: durable datasets, model artifacts, archives and long-lived results.

## 4. Compute tiers

### Tier A — daily/single-GPU development

Use the existing Nebius L40S-class single-GPU VM where appropriate.

Primary uses:

- NVIDIA driver and CUDA installation from a plain VM.
- NVIDIA Container Toolkit.
- Slurm GPU discovery/GRES.
- Pyxis/Enroot.
- Single-GPU real training.
- GPU/HBM monitoring.
- NUMA/PCIe inspection.
- Storage I/O experiments.
- Basic NCCL exercises that do not require an inter-node fabric.

The L40S tier is deliberately inexpensive enough for frequent short experiments. Prefer preemptible capacity where interruption is acceptable.

### Tier B — AI Factory/high-fidelity networking

Use Nebius GPU Cluster with H100 NVLink nodes and InfiniBand for the phases that require production-relevant GPU fabric behavior.

Target topology:

- 8 GPUs per GPU-cluster VM.
- H100 NVLink GPU configuration.
- InfiniBand fabric.
- GPU/NIC locality inspection.
- NCCL over RDMA.
- GPUDirect RDMA experiments.
- Multi-node distributed training.
- NVLink/NVSwitch topology analysis.

Do not keep this tier running continuously. Provision it only for the relevant experiments and destroy it afterward.

### H200

H200 is an optional later tier. Use it only when an experiment specifically benefits from its larger HBM capacity or when comparing GPU generations. It is not required for the baseline Lab 01 curriculum.

## 5. Persistent versus ephemeral resources

### Persistent / cheap

Keep these available when useful:

- Nebius VPC.
- Subnets.
- Security groups.
- Object Storage bucket.
- Shared filesystem.
- Small CPU-only controller VM.
- Small persistent monitoring/control services where required.

### Ephemeral / expensive

Create and destroy on demand:

- H100 GPU-cluster nodes.
- H200 GPU-cluster nodes.
- Large multi-GPU configurations.
- Temporary performance-test GPU nodes.

The rebuild workflow should therefore resemble:

```text
persistent foundation
        |
        +-- create GPU tier
        |
        +-- configure
        |
        +-- validate
        |
        +-- run workload
        |
        +-- collect evidence
        |
        +-- destroy GPU tier
        |
        +-- retain state/results
```

## 6. Controller VM

Initial target:

- 4–8 vCPU.
- 16–32 GB RAM.
- Approximately 100–200 GB network-backed SSD.

Expected future services:

- `slurmctld`.
- `slurmdbd`.
- MariaDB/PostgreSQL for Slurm accounting.
- Munge.
- Monitoring components.
- Administration/diagnostic tooling.
- Ansible control execution where practical.

The controller is deliberately CPU-only and inexpensive. It is not part of the GPU data path.

## 7. Shared filesystem

Use the Nebius-native shared filesystem rather than building a self-managed NFS server VM for the primary architecture.

Initial target: approximately 1 TiB.

Directory contract:

```text
/ai-factory/
├── models/
├── datasets/
├── checkpoints/
├── jobs/
└── shared/
```

The filesystem must survive GPU-node destruction so model and checkpoint state is independent of compute lifecycle.

Later experiments will compare shared filesystem, object storage and local storage where useful.

## 8. Object Storage

Create a small persistent Object Storage bucket for:

```text
models/
datasets/
artifacts/
training-results/
logs/
backups/
```

Object Storage is the durable artifact layer. It is intentionally separate from the POSIX filesystem used by active training jobs.

## 9. Networking

### Management plane

Nebius VPC/subnet provides:

- SSH.
- Slurm controller/daemon communication.
- Monitoring.
- Administrative access.
- Storage/control traffic as appropriate.

### GPU data plane

Nebius GPU Cluster InfiniBand provides the high-performance training fabric where supported.

We will explicitly inspect:

- `ip -br link`.
- `ip addr`.
- `ip route`.
- `lspci -nn`.
- `ibstat`.
- `ibdev2netdev`.
- `rdma link`.
- `show_gids` where installed.
- `nvidia-smi topo -m`.
- NCCL topology/debug output.

The goal is to understand the complete path rather than treating NCCL as a black box.

## 10. Storage model

```text
                 Durable data
                      |
             +--------+--------+
             |                 |
       Object Storage      Shared FS
             |                 |
     datasets/artifacts   active training
                           models/checkpoints
                                  |
                             GPU compute
                                  |
                             local disk
                         temporary/cache data
```

Later phases will measure throughput, latency, pressure and checkpoint behavior across these paths.

## 11. Software stack to be introduced later

The baseline architecture reserves for:

```text
OS
  -> NVIDIA driver
  -> CUDA toolkit/runtime
  -> NVIDIA Container Toolkit
  -> Slurm
  -> GRES/cgroup enforcement
  -> Slurm accounting/QOS
  -> Enroot
  -> Pyxis
  -> PyTorch/Hugging Face
  -> NCCL
  -> DCGM/exporters
```

Kubernetes/GPU Operator/DRA/Run:ai are intentionally separate labs and are not installed as part of the raw Slurm control plane.

## 12. Workload strategy

All meaningful performance phases must use real workloads.

Planned workload progression:

1. Real single-GPU model training.
2. Real checkpoint writes to shared storage.
3. GPU/HBM utilization and memory pressure measurement.
4. Single-node NCCL benchmarks.
5. Multi-node NCCL over InfiniBand/RDMA.
6. Real multi-node PyTorch distributed training.
7. Failure/recovery during training.
8. Later, separate Triton/vLLM/NIM inference lab.

The workload layer must expose enough activity to observe compute, memory, storage and network behavior simultaneously.

## 13. Cost/rebuild policy

Use the following daily lifecycle:

```text
START DAY
  |
  +-- verify persistent foundation
  |
  +-- create only required compute
  |
  +-- execute lab
  |
  +-- collect logs/metrics/results
  |
  +-- destroy expensive compute
  |
  +-- retain shared filesystem/object storage/results
  |
END DAY
```

Terraform will eventually model infrastructure lifecycle. Ansible will configure OS/software state. GitHub Actions will provide a single manually-triggered workflow per lab with phase/action selectors rather than one workflow per phase.

## 14. Automation boundary

Manual execution is authoritative until a phase is validated.

After validation:

```text
Manual commands
      |
      +--> Terraform resource definition
      |
      +--> Ansible configuration
      |
      +--> validation scripts
      |
      +--> GitHub Actions orchestration
```

Do not automate an unvalidated design.

## 15. Security model

- GitHub Actions uses a dedicated Nebius service account.
- Service-account credentials remain GitHub Environment secrets.
- SSH private keys remain GitHub Environment secrets.
- No credentials are committed to Git.
- Use project-scoped/least-privilege permissions wherever Nebius supports them.
- Separate infrastructure credentials from model-registry credentials.
- Add NGC/Hugging Face/Object Storage credentials only when the corresponding phase requires them.

## 16. Production-equivalent concepts

| AI Factory | Kubernetes/DevOps analogy |
|---|---|
| `slurmctld` | Kubernetes API/control-plane scheduling ecosystem |
| Munge | Node/control-plane trust mechanism; conceptually similar to transport/authentication trust, but not TLS itself |
| Slurm GRES | Device Plugin/resource advertisement + allocation |
| Slurm cgroups | Kubernetes resource isolation/cgroups |
| `sbatch` | Job manifest / workload submission |
| Pyxis + Enroot | Container runtime integration comparable to CRI/containerd workflow |
| Slurm partitions | Scheduling pools / workload classes |
| Slurm QOS | Priority, quota and policy controls |
| GPU Cluster + InfiniBand | Dedicated accelerator/data-plane fabric |
| NCCL | GPU collective communication library used by distributed frameworks |

These are conceptual mappings, not claims that the systems are implemented identically.

## 17. Phase 00 acceptance criteria

Phase 00 is complete only when the following are documented and validated against current Nebius capabilities:

- [ ] Target GPU SKU selected.
- [ ] Target Nebius GPU cluster configuration selected.
- [ ] H100/InfiniBand availability and quota checked for the project.
- [ ] Management VPC/subnet design defined.
- [ ] GPU data-plane architecture defined.
- [ ] Shared filesystem selected and sizing target defined.
- [ ] Object Storage bucket strategy defined.
- [ ] Controller sizing defined.
- [ ] Persistent versus ephemeral resources identified.
- [ ] Slurm architecture defined.
- [ ] GPU software stack defined.
- [ ] Pyxis/Enroot strategy defined.
- [ ] Monitoring strategy defined.
- [ ] Real training workload strategy defined.
- [ ] Multi-node/NCCL experiment topology defined.
- [ ] Failure-domain and maintenance strategy defined.
- [ ] Cost/rebuild lifecycle defined.
- [ ] GitHub Actions single-workflow-per-lab model defined.
- [ ] Phase 01 provisioning contract ready.

## 18. Authoritative external references

Nebius documentation must be checked again at provisioning time because SKU availability, regions, pricing and quotas can change:

- Compute GPU clusters: https://docs.nebius.com/compute/clusters/gpu
- Compute pricing: https://docs.nebius.com/compute/resources/pricing
- Storage: https://docs.nebius.com/compute/storage/types
- VPC: https://docs.nebius.com/vpc
- Terraform provider: https://docs.nebius.com/terraform-provider
- Nebius documentation home: https://docs.nebius.com/
