# Controller Snapshot Recovery Runbook

## Purpose

This runbook is the starting point for the next lab session.

The current controller VM will be powered off after the Phase 04 validation. Its disk snapshot is the persistent checkpoint.

The next controller should be created from that snapshot rather than rebuilt manually.

The key principle is:

> A disk snapshot preserves the software/control-plane state, but a newly created VM may have a different network identity.

Therefore every recovery starts with network and hostname verification.

---

# 1. Recovery architecture

Expected logical controller identity:

```text
Hostname: slurm-controller-01
Cluster:  ai-factory-lab
```

The private IP is **not fixed**.

The previous controller used:

```text
10.0.0.4
```

A snapshot-restored controller later used:

```text
10.0.0.0
```

The next recovery may receive another address.

Never copy the old address blindly.

---

# 2. Boot the new controller from the snapshot

Create a new controller VM using the preserved controller disk snapshot.

Use the same:

- VPC;
- subnet;
- security/firewall model;
- SSH access path;
- OS disk snapshot.

The controller does not need a GPU.

The goal is to restore the control plane first.

---

# 3. First login: establish current identity

Immediately run:

```bash
hostnamectl
hostname -f
ip -br addr
ip route
```

Record the current private IP.

Then restore the logical hostname if necessary:

```bash
sudo hostnamectl set-hostname slurm-controller-01
```

Verify:

```bash
hostnamectl --static
hostname -f
```

Expected logical hostname:

```text
slurm-controller-01
```

---

# 4. Verify controller services before changing configuration

Run:

```bash
systemctl is-active munge
systemctl is-active slurmctld
systemctl is-active slurmdbd
systemctl is-active mariadb
```

Then:

```bash
systemctl status munge --no-pager
systemctl status slurmctld --no-pager
systemctl status slurmdbd --no-pager
systemctl status mariadb --no-pager
```

Verify versions:

```bash
slurmctld -V
slurmdbd -V
mariadb --version
munged --version 2>/dev/null || true
```

---

# 5. Verify the accounting database

The snapshot should preserve the Phase 02 accounting state.

Check:

```bash
sacctmgr show cluster
sacctmgr show account
sacctmgr show user
```

Then:

```bash
sacctmgr show assoc
```

The expected lab identity is:

```text
Cluster: ai-factory-lab
Account: ai-factory
User:    jithin
```

Do not recreate these objects if they already exist.

The snapshot is intended to preserve them.

---

# 6. Verify Slurm controller health

Run:

```bash
scontrol ping
sinfo
scontrol show config | grep -E 'ClusterName|SlurmctldHost|SlurmctldPort|SlurmdPort|AccountingStorage'
```

At this point the workers may be powered off, so an unavailable-node state is not itself a failure.

The immediate objective is controller health.

---

# 7. Identify the controller IP used by Slurm

Inspect:

```bash
grep -E '^SlurmctldHost=' /etc/slurm/slurm.conf
```

Compare it with:

```bash
ip -br addr
```

If the configured address is stale, back up the configuration:

```bash
sudo cp /etc/slurm/slurm.conf   /etc/slurm/slurm.conf.before-snapshot-recovery
```

Then update the controller address to the current private IP.

Example:

```text
SlurmctldHost=slurm-controller-01(<CURRENT_CONTROLLER_PRIVATE_IP>)
```

Do not use the historical `10.0.0.4` unless the new VM actually received that address.

---

# 8. Validate controller configuration

Before restarting anything:

```bash
slurmctld -t
```

If the installed Slurm build does not support the exact validation option being used, use:

```bash
slurmctld -Dvvv
```

or inspect:

```bash
journalctl -u slurmctld --since "10 minutes ago" --no-pager
```

The exact installed version is authoritative for command availability.

---

# 9. Restart/reload only after configuration is correct

If the controller configuration changed:

```bash
sudo systemctl restart slurmctld
sudo systemctl restart slurmdbd
```

Then:

```bash
scontrol ping
systemctl is-active slurmctld
systemctl is-active slurmdbd
```

Do not restart healthy services repeatedly while debugging a worker problem.

---

# 10. Update the Git-managed controller address

The worker configuration receives the controller address from:

```text
labs/01-slurm-ai-factory/phase-03/ansible/inventories/lab/group_vars/all.yml
```

Update:

```yaml
slurm_controller_addr: <CURRENT_CONTROLLER_PRIVATE_IP>
```

The controller address is intentionally not hard-coded into worker documentation.

The exact IP belongs to the current infrastructure instance.

Commit the change before creating/reconfiguring workers.

Example:

```bash
git add labs/01-slurm-ai-factory/phase-03/ansible/inventories/lab/group_vars/all.yml
git commit -m "Update lab controller address after snapshot recovery"
git push
```

---

# 11. Fresh worker creation

When the next phase requires GPU workers, create fresh Nebius L40S workers.

Do not reuse the old worker IP addresses.

For each worker, collect:

```bash
hostnamectl
ip -br addr
uname -a
nproc
free -m
nvidia-smi
nvidia-smi -L
nvcc --version
slurmd -C
```

The most important new Slurm evidence is:

```bash
slurmd -C
```

This reports the actual hardware configuration in Slurm syntax.

Do not manually assume:

```text
CPUs=16
RealMemory=96556
```

or any other value from an old VM.

The Phase 04 workers registered with:

```text
CPUs=8
RealMemory=32094
ThreadsPerCore=1
```

but future instances must be verified again.

Official reference:

https://slurm.schedmd.com/slurmd.html

---

# 12. Update Ansible inventory

Edit:

```text
labs/01-slurm-ai-factory/phase-03/ansible/inventories/lab/hosts.yml
```

Example:

```yaml
gpu_workers:
  hosts:
    l40-node-01:
      ansible_host: <NEW_WORKER_01_IP>
    l40-node-02:
      ansible_host: <NEW_WORKER_02_IP>
```

Keep the logical names stable even if the cloud instances are replaced.

Then test:

```bash
cd labs/01-slurm-ai-factory/phase-03/ansible

ansible all -i inventories/lab/hosts.yml -m ping
```

---

# 13. Run Ansible worker convergence

Run:

```bash
ansible-playbook   -i inventories/lab/hosts.yml   playbooks/gpu-node.yml
```

Then validate separately:

```bash
ansible-playbook   -i inventories/lab/hosts.yml   playbooks/validate-gpu-node.yml
```

The expected worker validation includes:

```text
NVIDIA device: /dev/nvidia0 present
cgroup filesystem: cgroup2fs
MUNGE: active
slurmd: active
GRES: validated
```

---

# 14. Validate worker hardware before changing controller node definitions

On each worker:

```bash
slurmd -C
slurmd -G
```

Record both outputs in the phase documentation.

The controller's `NodeName` definitions must agree with the actual worker resources.

Official Slurm documentation notes that node definitions should establish the baseline resources and that nodes registering with less than the configured resources can be placed DOWN.

Reference:

https://slurm.schedmd.com/slurm.conf.html

---

# 15. Validate Slurm registration

On the controller:

```bash
sinfo
```

Then:

```bash
scontrol show node l40-node-01
scontrol show node l40-node-02
```

For concise validation:

```bash
scontrol show node l40-node-01 |
  grep -E 'State=|Reason=|CPUTot=|RealMemory='

scontrol show node l40-node-02 |
  grep -E 'State=|Reason=|CPUTot=|RealMemory='
```

Healthy result:

```text
State=IDLE
```

and no registration failure reason.

---

# 16. If a node becomes INVALID_REG

Do not immediately restart everything.

First inspect:

```bash
scontrol show node <NODE>
```

Look specifically for:

```text
State=
Reason=
CPUTot=
RealMemory=
ThreadsPerCore=
```

Then compare with the worker:

```bash
slurmd -C
```

The common failure seen in this lab was:

```text
controller configured:
CPUs=16
RealMemory=96556

worker reported:
CPUs=8
RealMemory=32094
```

That produced:

```text
State=DOWN+INVALID_REG
Reason=Low socket*core*thread count,
       Low CPUs,
       Low RealMemory
```

Fix the node definition from verified hardware data, then reconfigure Slurm.

---

# 17. If a node becomes NOT_RESPONDING

First determine whether this is a Slurm problem or an OS/VM problem.

From the controller:

```bash
scontrol show node <NODE>
nc -vz <WORKER_IP> 6818
```

Then try:

```bash
ssh <WORKER>
```

If SSH is unavailable, do not waste time changing Slurm configuration.

Use the cloud control plane to determine whether the VM is healthy.

If the VM is healthy and reachable, inspect:

```bash
systemctl status munge --no-pager
systemctl status slurmd --no-pager
journalctl -u slurmd --since "10 minutes ago" --no-pager
journalctl -u munge --since "10 minutes ago" --no-pager
```

---

# 18. If MUNGE reports Invalid credential

Run on both sides:

```bash
systemctl is-active munge
munge -n | unmunge
sha256sum /etc/munge/munge.key
stat /etc/munge/munge.key
timedatectl
```

Verify the keys are identical.

Then perform a true cross-node test.

Do not conclude "wrong key" merely from:

```text
Munge decode failed: Invalid credential
```

The Phase 04 incident showed why: local MUNGE was healthy and the exact transient cause was not conclusively established.

---

# 19. Final GPU acceptance test

Only after both nodes are IDLE:

```bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1   nvidia-smi
```

Then verify CUDA:

```bash
srun --partition=gpu --gres=gpu:1 --nodes=1 --ntasks=1   bash -lc 'nvcc --version'
```

Finally execute a real CUDA kernel.

The Phase 04 reference implementation produced:

```text
CUDA execution successful
c[0] = 3.0
c[N-1] = 3.0
```

Do not install PyTorch just to prove that the infrastructure works. PyTorch belongs to the later application/container layer.

---

# 20. Shutdown / cost control

When the current phase is complete:

1. Stop running jobs.
2. Verify `squeue`.
3. Collect final validation evidence.
4. Commit documentation.
5. Power off GPU workers.
6. Power off the controller if no control-plane work is pending.
7. Keep the controller disk snapshot.
8. Keep the Git repository.
9. Keep the MUNGE key securely out-of-band.

Check:

```bash
squeue
sinfo
sacct --starttime now-1day
```

No expensive GPU VM needs to remain running between phases.

---

# 21. Recovery invariant

Every fresh session should follow:

```text
Snapshot
   ↓
Current network identity
   ↓
Controller health
   ↓
Accounting health
   ↓
Git controller address
   ↓
Fresh worker hardware discovery
   ↓
Ansible convergence
   ↓
slurmd -C
   ↓
Slurm registration
   ↓
GPU allocation
   ↓
Real CUDA workload
   ↓
Document
   ↓
Power off
```

This sequence intentionally prevents the team from debugging higher layers before lower layers are known to be healthy.

---

# 22. Important files

```text
labs/01-slurm-ai-factory/phase-03/
├── PHASE-03-ANSIBLE-ARCHITECTURE.md
├── ansible/
│   ├── inventories/lab/hosts.yml
│   ├── inventories/lab/group_vars/all.yml
│   ├── playbooks/gpu-node.yml
│   ├── playbooks/validate-gpu-node.yml
│   └── secrets/README.md
└── tools/validate-ansible.sh

labs/01-slurm-ai-factory/phase-04/
├── PHASE-04-RUNTIME-VALIDATION-AND-INCIDENTS.md
└── CONTROLLER-SNAPSHOT-RECOVERY.md
```

---

# 23. Future automation boundary

The current recovery procedure is deliberately explicit.

The next automation work should eventually turn the stable portions into scripts/workflows:

- controller recovery preflight;
- network identity discovery;
- Ansible inventory update;
- worker provisioning;
- worker convergence;
- hardware discovery;
- Slurm registration validation;
- GPU smoke test;
- shutdown/destroy.

Do not automate an unstable process by hiding its failure modes.

First make the manual runbook reliable; then automate the exact sequence.

---

# Final rule

> **A snapshot is a recovery artifact, not a substitute for configuration management.**

The snapshot preserves the controller's state. Git preserves the intended configuration and the operational knowledge. Ansible recreates worker state. Cloud provisioning recreates infrastructure.

The combination is the actual rebuild system.
