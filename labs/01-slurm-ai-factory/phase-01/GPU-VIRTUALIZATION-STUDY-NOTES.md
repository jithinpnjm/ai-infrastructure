# Lab 01 — Phase 01: GPU Virtualization and SR-IOV Study Notes

## Purpose

This document captures an important **unresolved study area** identified while inspecting the first Nebius L40S compute node.

The topic is important for understanding AI factories because GPU virtualization, PCIe virtualization, SR-IOV, NVIDIA vGPU, MIG, and PCIe passthrough are related but **not interchangeable concepts**.

This document deliberately separates:

1. What we observed on the Nebius VM
2. What that observation proves
3. What it does not prove
4. The concepts that need to be studied
5. Questions that must be answered in later phases

The objective is to avoid creating false certainty from incomplete guest-side evidence.

---

# 1. Observation from the manual L40S node

The first compute node was a Nebius VM exposing an NVIDIA L40S GPU to Ubuntu.

Inside the guest we observed a normal NVIDIA software path:

```text
lspci
  ↓
NVIDIA L40S visible
  ↓
NVIDIA kernel driver
  ↓
/dev/nvidia0
  ↓
nvidia-smi
  ↓
CUDA
  ↓
real CUDA kernel execution
```

The GPU was functional from the guest operating system's perspective.

However, PCIe inspection produced an interesting result.

Using:

```bash
lspci -vv -s <PCI_BUS_ID>
```

we observed values equivalent to:

```text
LnkCap: 16GT/s x16
LnkSta: 2.5GT/s x16
```

Interpretation:

```text
LnkCap
  = reported link capability
  = 16 GT/s x16
  = PCIe Gen4 x16 capability

LnkSta
  = current negotiated link
  = 2.5 GT/s x16
  = PCIe Gen1 x16 negotiated state
```

The device therefore reported a higher capability than the link speed currently negotiated in the guest-visible environment.

---

# 2. What this observation proves

It proves that the guest-visible PCIe device reported:

```text
Capability: 16 GT/s x16
Negotiated: 2.5 GT/s x16
```

It also proves that the L40S was usable by the guest for CUDA workloads.

It does **not** by itself prove that the GPU was:

- NVIDIA vGPU
- SR-IOV virtual function
- mediated device
- PCIe passthrough
- bare-metal PCIe attachment

Those are different attachment/virtualization mechanisms.

The exact host-side GPU attachment mechanism used by the Nebius VM was **not established during Phase 01**.

This remains a deliberate grey area for future study.

---

# 3. PCIe virtualization is not the same thing as NVIDIA vGPU

This distinction is important in interviews and architecture discussions.

A cloud VM can receive a GPU through a virtualization/passthrough mechanism while still presenting a full NVIDIA GPU device to the guest.

Conversely, NVIDIA vGPU is a specific technology/model for sharing a physical GPU among virtual machines using virtual GPU instances/profiles.

Therefore:

```text
GPU visible in a VM
        ≠
NVIDIA vGPU
```

and:

```text
PCIe virtualization
        ≠
SR-IOV
        ≠
NVIDIA vGPU
        ≠
MIG
```

These technologies need to be understood separately and then compared.

---

# 4. What is SR-IOV?

**SR-IOV = Single Root I/O Virtualization.**

It is a PCIe virtualization standard that allows a physical PCIe device to expose multiple virtual PCIe functions.

The key concepts are:

```text
Physical Function (PF)
        |
        +---- Virtual Function (VF)
        +---- Virtual Function (VF)
        +---- Virtual Function (VF)
        +---- ...
```

The PF is the full physical-device function controlled by the host/hypervisor.

VFs are lightweight PCIe functions that can be assigned to virtual machines.

The purpose is to reduce virtualization overhead and provide more direct device access to guests.

---

# 5. SR-IOV in a GPU context

The high-level model is:

```text
                  Physical GPU / PCIe device
                           |
                           v
                    Physical Function
                           |
             +-------------+-------------+
             |             |             |
             v             v             v
            VF0           VF1           VF2
             |             |             |
             v             v             v
            VM1           VM2           VM3
```

The guest can receive a VF as a PCIe device.

This can provide much more direct I/O access than a traditional emulated virtual device.

However, **SR-IOV itself does not define how GPU compute resources are partitioned**.

That distinction is critical.

For GPUs, resource partitioning can involve mechanisms such as:

- NVIDIA vGPU
- MIG
- vendor-specific virtualization
- time-slicing
- passthrough

SR-IOV can be part of the infrastructure used to expose virtual functions, but it should not be casually described as synonymous with GPU sharing.

---

# 6. Physical Function vs Virtual Function

## Physical Function

The PF is the full PCIe function associated with the physical device.

Conceptually:

```text
Host
 └── PF
      └── controls/configures device virtualization
```

## Virtual Function

A VF is a lightweight PCIe function created by an SR-IOV-capable device.

Conceptually:

```text
PF
 ├── VF0 → VM A
 ├── VF1 → VM B
 └── VF2 → VM C
```

The guest can communicate with its assigned VF without requiring the hypervisor to emulate every I/O operation.

This is one of the reasons SR-IOV is attractive for high-performance workloads.

---

# 7. Why SR-IOV matters in an AI factory

AI factories are extremely sensitive to data movement and communication overhead.

The workload may involve:

```text
CPU
 ↓
PCIe
 ↓
GPU
 ↓
GPU memory/HBM
```

and, in distributed systems:

```text
GPU
 ↓
PCIe / NIC
 ↓
network fabric
 ↓
NIC / PCIe
 ↓
GPU
```

Virtualization overhead can become significant for high-throughput GPU workloads.

A high-performance AI infrastructure therefore cares about:

- direct device access
- I/O virtualization overhead
- DMA
- PCIe topology
- NUMA locality
- GPU/NIC locality
- interrupt handling
- peer-to-peer access
- GPUDirect RDMA
- network fabric performance

SR-IOV is relevant because it can provide efficient device virtualization while retaining strong isolation between tenants/VMs.

---

# 8. SR-IOV is not the same as GPU memory partitioning

This is a common interview trap.

SR-IOV answers approximately:

> How can one physical PCIe device expose multiple virtual PCIe functions?

A GPU partitioning technology answers a different question:

> How are compute, memory and/or GPU resources divided among workloads?

For example, NVIDIA MIG provides hardware-partitioned GPU instances on supported GPUs.

Conceptually:

```text
Physical GPU
      |
      +---- GPU instance A
      +---- GPU instance B
      +---- GPU instance C
```

The resource semantics are different from simply exposing multiple PCIe functions.

Therefore:

```text
SR-IOV → I/O virtualization
MIG    → GPU hardware partitioning
vGPU   → virtual GPU abstraction/profile
```

There can be interactions between these technologies in a complete virtualization stack, but they should not be collapsed into one concept.

---

# 9. GPU passthrough vs SR-IOV

### PCIe passthrough

High-level model:

```text
Physical GPU
      |
      v
Hypervisor
      |
      | assign device directly
      v
VM
```

The VM receives direct ownership/access to the assigned physical device.

Typically this means the GPU is not simultaneously being divided among several VMs through the same assignment.

### SR-IOV

High-level model:

```text
Physical device
      |
      v
PF
 ├── VF0 → VM1
 ├── VF1 → VM2
 └── VF2 → VM3
```

Multiple VMs can receive separate virtual functions from the same physical device, subject to the device/vendor implementation.

### Key distinction

```text
Passthrough
  = direct device assignment

SR-IOV
  = multiple virtual PCIe functions from one physical device
```

---

# 10. NVIDIA vGPU vs SR-IOV

NVIDIA vGPU is a higher-level GPU virtualization mechanism that provides virtual GPU instances/profiles to VMs.

A simplified conceptual stack is:

```text
Physical GPU
      |
      v
GPU virtualization layer
      |
      +---- vGPU profile A → VM1
      +---- vGPU profile B → VM2
      +---- vGPU profile C → VM3
```

The guest sees a virtual GPU rather than necessarily owning the entire physical GPU.

NVIDIA documents different vGPU profiles for supported GPU products.

The important interview answer is:

> SR-IOV is a PCIe/device virtualization mechanism; NVIDIA vGPU is a GPU virtualization technology. They operate at different conceptual layers even when an implementation uses SR-IOV underneath or alongside the virtualization architecture.

The exact implementation depends on the GPU generation, hypervisor, vendor software stack and cloud platform.

---

# 11. Why our L40S observation cannot identify the mechanism

We saw:

```text
Guest Linux
   |
   +-- NVIDIA L40S
   +-- /dev/nvidia0
   +-- nvidia-smi works
   +-- CUDA works
   +-- PCIe capability reported
   +-- negotiated link reported
```

That is insufficient to conclude:

```text
"It is vGPU."
```

or:

```text
"It is SR-IOV."
```

The correct engineering statement is:

> The guest received an NVIDIA L40S through the cloud platform's GPU virtualization/attachment infrastructure. The guest-side observations established GPU functionality and the reported PCIe capability/negotiated state, but Phase 01 did not establish the exact host-side attachment mechanism.

This is the statement we should use until we verify the platform implementation.

---

# 12. Why the PCIe Gen1 observation matters

The observation:

```text
LnkCap: 16GT/s x16
LnkSta: 2.5GT/s x16
```

raises an important performance question.

Approximate raw per-lane PCIe transfer rates are:

```text
Gen1: 2.5 GT/s
Gen2: 5.0 GT/s
Gen3: 8.0 GT/s
Gen4: 16.0 GT/s
Gen5: 32.0 GT/s
```

Therefore, a guest-visible Gen1 link can have dramatically lower effective bandwidth than a Gen4-capable device.

This does **not** automatically mean the GPU is unhealthy.

It means the effective I/O path needs to be understood before drawing performance conclusions.

The correct next step is benchmarking rather than assuming.

---

# 13. What we should investigate in a future phase

When we return to GPU virtualization, collect evidence from both the guest and, where the cloud provider exposes it, the infrastructure layer.

## Guest-side evidence

```bash
lspci -nn
lspci -vv -s <bus-id>
lspci -vvv -s <bus-id>
cat /sys/bus/pci/devices/<BDF>/vendor
cat /sys/bus/pci/devices/<BDF>/device
cat /sys/bus/pci/devices/<BDF>/sriov_totalvfs
cat /sys/bus/pci/devices/<BDF>/sriov_numvfs
readlink /sys/bus/pci/devices/<BDF>/driver
nvidia-smi -q
nvidia-smi -q -d PCI
nvidia-smi topo -m
```

Not every command/file is expected to exist on every GPU or virtualization mode. Their absence is itself useful evidence.

## Host/cloud-side questions

For the cloud platform, determine:

- Is the GPU passed through directly?
- Is the GPU exposed through SR-IOV?
- Is NVIDIA vGPU used?
- Is a mediated device used?
- Is the GPU a dedicated physical allocation to the VM?
- Is the PCIe device emulated, virtualized or directly assigned?
- How is GPU isolation implemented?
- How is GPU memory isolation implemented?
- How is DMA isolation implemented?
- What happens to PCIe bandwidth under virtualization?
- What topology does the guest see versus the physical host?

These questions should be answered from provider documentation and controlled experiments, not assumptions.

---

# 14. Relationship to future AI-factory networking

This topic becomes significantly more important once the lab moves from one GPU to distributed training.

The eventual communication path may look like:

```text
GPU 0
  |
  | PCIe
  v
NIC 0
  |
  | InfiniBand / Ethernet
  v
NIC 1
  |
  | PCIe
  v
GPU 1
```

For high-performance distributed training we then need to understand:

```text
PCIe
 ↓
NUMA
 ↓
NIC locality
 ↓
DMA
 ↓
GPUDirect RDMA
 ↓
InfiniBand
 ↓
NCCL
```

Virtualization can affect multiple points in this path.

That is why the current PCIe observation should not be dismissed as an isolated `lspci` curiosity.

---

# 15. Interview study questions

These questions should remain in the lab knowledge base and be revisited after the networking phases.

### Fundamentals

1. What is SR-IOV?
2. What is a Physical Function?
3. What is a Virtual Function?
4. Why is SR-IOV useful for high-performance workloads?
5. What is PCIe passthrough?
6. What is a mediated device?
7. What is NVIDIA vGPU?
8. What is NVIDIA MIG?
9. How are SR-IOV, vGPU and MIG different?
10. Can SR-IOV itself partition GPU compute resources?

### AI infrastructure

11. Why does GPU virtualization matter for AI factories?
12. How can virtualization affect GPU I/O performance?
13. Why does PCIe topology matter for GPU training?
14. Why does NUMA locality matter?
15. Why does GPU/NIC locality matter for NCCL?
16. How does GPUDirect RDMA change the communication path?
17. What isolation mechanisms prevent one VM from accessing another VM's GPU resources?
18. How does a cloud provider expose GPUs to a VM while maintaining tenant isolation?

### Troubleshooting

19. `lspci` sees the GPU but `nvidia-smi` fails — where do you investigate?
20. `nvidia-smi` works but CUDA fails — what layers could be broken?
21. `LnkCap` is Gen4 but `LnkSta` is Gen1 — what does that mean?
22. How would you determine whether a PCIe device is an SR-IOV VF?
23. How would you distinguish passthrough from vGPU from guest-side evidence?
24. How would you prove whether PCIe bandwidth is actually limiting training performance?

---

# 16. Current knowledge boundary

At the end of Phase 01:

### Proven

```text
Nebius VM
   ↓
L40S visible to guest
   ↓
NVIDIA driver functional
   ↓
CUDA functional
   ↓
Real GPU computation functional
   ↓
PCIe capability reported as 16GT/s x16
   ↓
PCIe negotiated state observed as 2.5GT/s x16
```

### Not yet proven

```text
Exact host-side GPU attachment mechanism
        |
        +-- PCIe passthrough?
        +-- SR-IOV?
        +-- NVIDIA vGPU?
        +-- mediated device?
        +-- provider-specific mechanism?
```

### Future validation

```text
Guest PCIe evidence
        +
Cloud-provider architecture
        +
Controlled performance tests
        ↓
Verified virtualization model
```

This uncertainty is intentional and should remain visible in the documentation until resolved.

---

# Status

**Phase 01 study note — open for future expansion.**

This document is a knowledge placeholder for GPU virtualization and SR-IOV. It should be expanded when the lab reaches virtualization, networking, GPUDirect RDMA, NCCL and multi-tenant GPU architecture topics.
