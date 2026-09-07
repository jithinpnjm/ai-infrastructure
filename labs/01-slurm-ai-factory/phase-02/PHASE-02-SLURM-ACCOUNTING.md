# Phase 02 — Slurm Accounting

## Objective

Integrate Slurm accounting into the Phase 01 controller without recreating the deleted manual GPU node.

The goal is to understand and prove the **accounting plane** independently from the compute/workload plane:

```text
                         Control plane
                    +---------------------+
                    |                     |
                    | slurmctld :6817    |
                    |                     |
                    +----------+----------+
                               |
                               | Slurm accounting RPC :6819
                               v
                    +---------------------+
                    | slurmdbd :6819      |
                    +----------+----------+
                               |
                               | MySQL protocol :3306
                               v
                    +---------------------+
                    | MariaDB             |
                    | slurm_acct_db       |
                    +---------------------+
```

Phase 02 deliberately does **not** recreate `l40-node-01`. A real compute node will be introduced in later phases and used for successful workload/accounting and failure/recovery tests.

---

## Why Slurm Accounting Exists

Slurm scheduling answers questions such as:

- Can this job run?
- Which node/GPU/CPU should it use?
- Is the requested resource available?

Accounting answers a different set of questions:

- Who submitted the job?
- Which project/account should be charged or attributed?
- Which cluster ran it?
- How many CPUs, GPUs, memory, or other TRES were allocated?
- How long did it run?
- How much resource usage accumulated over time?
- Should a user/project be allowed to exceed a configured quota or fair-share policy?

In a production AI factory, this separation is important. Scheduling provides resource allocation; accounting provides **identity, ownership, usage history, chargeback/showback, quotas, fair-share inputs, and governance**.

---

## Cluster / Organization / Account / User — What They Mean

These concepts are easy to confuse because "account" and "organization" can mean different things outside Slurm.

### Cluster

A Slurm **cluster** is the Slurm control domain managed by a `slurmctld` instance.

This lab cluster is:

```text
ai-factory-lab
```

It identifies the scheduler/control domain from which jobs and accounting records originate.

A company could have one Slurm cluster or multiple clusters/regions. SlurmDBD can aggregate accounting information from multiple Slurm clusters into one accounting database.

### Account

A Slurm **account** is primarily a logical ownership/project/billing grouping. It is not the same thing as a Linux account and does not mean a login identity.

Example:

```text
ai-factory
```

A production company might create accounts such as:

```text
research
research-llm
computer-vision
platform-team
customer-a
customer-b
```

The account can then be associated with users and, through associations/QOS/limits, used to control who may consume which resources.

For example:

```text
account: research-llm
  MaxTRES: gpu=32
  GrpTRES: gpu=64
```

The exact policy is a production design decision; this phase only establishes the identity/accounting model.

### User

The Slurm **user** is the identity submitting the job, normally corresponding to the Unix/Linux user identity on the compute environment.

This lab uses:

```text
jithin
```

The association created is:

```text
cluster: ai-factory-lab
  account: ai-factory
    user: jithin
```

The user also has `ai-factory` as its default account.

### Organization

`Org` shown by `sacctmgr` is not a separate Slurm hierarchy equivalent to Microsoft Entra ID organizations/tenants. It is an accounting/account attribute used by Slurm for account organization/ownership semantics.

For this lab:

```text
Account: ai-factory
Org:     ai-factory
```

We should **not** interpret this as meaning that an Entra organization or tenant must map one-to-one to a Slurm `Org`.

---

## Production Relevance

A realistic AI platform may look like:

```text
Company / Entra tenant
        |
        +-- AI Platform
              |
              +-- Slurm cluster: eu-prod
              |
              +-- Accounts / projects
                    |
                    +-- llm-research
                    |     +-- alice
                    |     +-- bob
                    |
                    +-- cv-research
                    |     +-- carol
                    |
                    +-- customer-acme
                          +-- service-user / users
```

The important design principle is:

> **Identity provider identity is not the same thing as Slurm accounting ownership.**

Entra ID can answer **who the person is**. Slurm accounts answer **which project/resource pool that person's workload belongs to**.

A user may therefore belong to one or more Slurm accounts/projects, depending on the company's governance model.

This becomes important when implementing GPU quotas, fair-share, chargeback/showback, customer isolation, or project-level resource limits.

---

# Phase 02 Scope

1. Install MariaDB.
2. Create the Slurm accounting database.
3. Create the MariaDB service user and permissions.
4. Install SlurmDBD.
5. Configure `slurmdbd.conf`.
6. Validate SlurmDBD → MariaDB connectivity.
7. Configure `slurmctld` to use SlurmDBD.
8. Register the Slurm cluster.
9. Create the `ai-factory` accounting account.
10. Associate the `jithin` user.
11. Configure the default account.
12. Submit a real CPU-only job request and validate its accounting record.
13. Document observations and operational behavior.

### Explicitly deferred

- New GPU nodes.
- Ansible onboarding.
- Distributed GPU workloads.
- MPI/PMIx/NCCL.
- InfiniBand/network performance.
- SlurmDBD failure/recovery test.

The SlurmDBD failure/recovery test is intentionally deferred until a real compute node and real workload are available. We do not want to infer production behavior from a controller-only setup.

---

# 1. Controller Baseline

The existing controller was retained from Phase 01:

```text
Hostname:  slurm-controller-01
IP:        10.0.0.4
OS:        Ubuntu 24.04.4 LTS
Slurm:     23.11.4
MUNGE:     active
slurmctld: active
Cluster:   ai-factory-lab
```

The Phase 01 GPU node `l40-node-01` had already been deleted. It remains configured in Slurm but is unavailable/down.

This is intentional: Phase 02 is about accounting, not rebuilding the compute plane.

---

# 2. Install MariaDB

Installed:

```text
mariadb-server 1:10.11.14-0ubuntu0.24.04.1
```

MariaDB is the persistent backend used by SlurmDBD in this architecture.

Commands used:

```bash
apt update
apt install mariadb-server
systemctl enable --now mariadb
```

### What the commands do

- `apt update` refreshes the package index.
- `apt install mariadb-server` installs the database server.
- `systemctl enable --now mariadb` enables MariaDB at boot and starts it immediately.

Validation:

```bash
systemctl status mariadb --no-pager
mysql -e "SELECT VERSION();"
mysql -e "SHOW VARIABLES LIKE 'bind_address';"
```

The database was bound to localhost (`127.0.0.1`). This is appropriate because MariaDB is only needed locally by SlurmDBD in this architecture; there is no reason to expose port 3306 to the network.

InnoDB was confirmed available/default. Slurm accounting relies on transactional database behavior.

---

# 3. Create the Slurm Accounting Database

Created:

```text
Database: slurm_acct_db
User:     slurm@localhost
```

The database user was granted:

```text
ALL privileges on slurm_acct_db.*
```

Validation was performed by logging in as the `slurm` DB user and confirming:

```text
CURRENT_USER() = slurm@localhost
```

Initially the database contained no Slurm tables. This was expected because SlurmDBD creates/initializes its schema.

---

# 4. Install SlurmDBD

Installed:

```text
slurmdbd 23.11.4-1.2ubuntu5
```

The package version intentionally matches the installed Slurm version.

Command:

```bash
apt install slurmdbd
```

The systemd unit runs the daemon as:

```text
User=slurm
Group=slurm
```

The service also has a condition requiring `/etc/slurm/slurmdbd.conf` to exist.

---

# 5. Configure `/etc/slurm/slurmdbd.conf`

The final configuration was:

```ini
AuthType=auth/munge

DbdHost=localhost
DbdPort=6819

DebugLevel=info

StorageHost=localhost
StorageLoc=slurm_acct_db
StoragePass=<DB_PASSWORD>
StoragePort=3306
StorageType=accounting_storage/mysql
StorageUser=slurm

LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurmdbd.pid

SlurmUser=slurm
```

`StoragePass` is represented as `<DB_PASSWORD>` here for documentation. The actual password must never be committed to Git.

Permissions:

```bash
chown slurm:slurm /etc/slurm/slurmdbd.conf
chmod 600 /etc/slurm/slurmdbd.conf
```

### Why these permissions matter

`slurmdbd.conf` contains the database password. It should therefore not be readable by ordinary users.

`chmod 600` means only the file owner can read/write it. `chown slurm:slurm` makes the daemon user the owner.

---

# 6. Start and Validate SlurmDBD

A foreground test was performed with:

```bash
slurmdbd -Dvvv
```

`-D` keeps the daemon in the foreground. `-vvv` increases diagnostic verbosity.

Successful output included:

```text
slurmdbd version 23.11.4 started
Attempting to connect to localhost:3306
as_mysql_roll_usage: Everything rolled up
```

This proved that SlurmDBD could initialize and connect to MariaDB.

SlurmDBD was then moved to the normal systemd-managed operating mode:

```bash
systemctl start slurmdbd
systemctl status slurmdbd --no-pager
```

Final status:

```text
Active: active (running)
```

The schema was validated with:

```bash
mysql -e "USE slurm_acct_db; SHOW TABLES;"
```

The following tables were present:

```text
acct_coord_table
acct_table
clus_res_table
cluster_table
convert_version_table
federation_table
qos_table
res_table
table_defs_table
txn_table
tres_table
user_table
```

### Observed warnings

SlurmDBD reported database tuning warnings such as `innodb_buffer_pool_size` and `innodb_lock_wait_timeout` not having recommended values. These did not prevent startup and were not changed in this lab.

The service also reported that it was not running as root and could not drop supplementary groups. This is consistent with the packaged systemd unit running SlurmDBD as the `slurm` user.

An unset optional environment variable was also reported by systemd but did not prevent startup.

These observations are recorded rather than hidden because they are useful operational knowledge.

---

# 7. Configure `slurmctld` to Use SlurmDBD

Before Phase 02, `scontrol show config` showed:

```text
AccountingStorageType = (null)
AccountingStoragePort = 0
```

The controller was changed to:

```ini
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
AccountingStoragePort=6819
```

### What these settings mean

- `AccountingStorageType` selects SlurmDBD as the accounting backend.
- `AccountingStorageHost` tells `slurmctld` where SlurmDBD runs.
- `AccountingStoragePort` selects SlurmDBD's RPC port.

The control and accounting planes therefore use different ports:

```text
slurmctld :6817  →  slurmd :6818     Control plane
slurmctld :6819  →  slurmdbd :6819    Accounting service endpoint
slurmdbd  :3306  →  MariaDB :3306     Persistence
```

MUNGE remains the authentication mechanism used by Slurm components.

After changing `slurm.conf`, the controller was restarted through systemd:

```bash
systemctl restart slurmctld
```

Then:

```bash
scontrol show config | grep -E '^ClusterName|^AccountingStorage'
```

confirmed:

```text
AccountingStorageHost   = localhost
AccountingStoragePort   = 6819
AccountingStorageType   = accounting_storage/slurmdbd
ClusterName             = ai-factory-lab
```

### Troubleshooting: `slurmctld -t`

An attempt was made to use:

```bash
slurmctld -t
```

as a configuration validation step. In this environment/Slurm build it attempted to initialize the daemon and bind port 6817, producing:

```text
Error binding slurm stream socket: Address already in use
```

The running systemd-managed `slurmctld` was healthy. We therefore stopped using `slurmctld -t` as a validation method in this environment and validated the loaded configuration through `scontrol show config` and the running daemon.

This is a useful operational lesson: do not blindly assume that a daemon option provides a non-starting configuration test; verify its behavior for the installed version/build.

---

# 8. Register the Slurm Cluster

Once `AccountingStorageType=accounting_storage/slurmdbd` was active, this command became available:

```bash
sacctmgr show cluster
```

The cluster record was present as:

```text
ai-factory-lab
ControlHost = 127.0.0.1
ControlPort = 6817
```

`sacctmgr` is the administrative interface for Slurm accounting objects such as clusters, accounts, users, associations, QOS, and limits.

Before enabling the SlurmDBD accounting plugin, `sacctmgr` reported:

```text
You are not running a supported accounting_storage plugin
Only 'accounting_storage/slurmdbd' is supported.
```

That failure was expected and demonstrated that the controller had not yet been connected to the accounting backend.

---

# 9. Create the Accounting Account

Created:

```bash
sacctmgr -i add account ai-factory
```

`-i` means perform the operation immediately/non-interactively rather than waiting for an interactive confirmation.

Validation:

```bash
sacctmgr show account
```

Result included:

```text
ai-factory
root
```

The `root` accounting account already existed and was not used for the lab workload.

---

# 10. Create the User Association

The controller contained these interactive Linux users:

```text
ubuntu:1000:/home/ubuntu:/bin/bash
jithin:1001:/home/jithin:/bin/bash
```

The lab uses the non-root `jithin` identity.

Created the association:

```bash
sacctmgr -i add user jithin account=ai-factory cluster=ai-factory-lab
```

This establishes the relationship:

```text
Cluster: ai-factory-lab
  Account: ai-factory
    User: jithin
```

The association is important because Slurm needs to know not only **who** submitted a job but also **which project/account owns the workload**.

A production GPU platform can use this relationship to apply project/user-level policies such as:

- GPU quotas
- CPU/memory limits
- maximum concurrent jobs
- QOS selection
- fair-share weighting
- chargeback/showback
- project isolation

---

# 11. Configure the Default Account

The default account for `jithin` was set to `ai-factory`.

Validation:

```bash
sacctmgr show user jithin withassoc format=User,DefaultAccount,Cluster,Account
```

Result:

```text
User    Def Acct    Cluster        Account
jithin  ai-factory  ai-factory-lab  ai-factory
```

The default account means a job submitted by this user does not need to specify `--account=ai-factory` every time, provided the association/policy permits the job.

---

# 12. Accounting Validation with a Real Job Submission

The physical GPU node had intentionally been deleted, so a CPU-only job was used for the accounting validation.

The submitted command was:

```bash
srun --job-name=accounting-test --cpus-per-task=2 --mem=512M --time=00:01:00 hostname
```

### What the command does

- `srun` submits/runs a Slurm job step.
- `--job-name=accounting-test` gives the job a recognizable name.
- `--cpus-per-task=2` requests two CPUs.
- `--mem=512M` requests 512 MiB of memory.
- `--time=00:01:00` sets a one-minute time limit.
- `hostname` is the actual command that would execute on an allocated node.

Because there were no available compute nodes, Slurm reported:

```text
Required node not available (down, drained or reserved)
job 9 queued and waiting for resources
```

The job was subsequently cancelled because the required node was unavailable.

The accounting record was queried with:

```bash
sacct -j 9 \
  --starttime=$(date -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%S') \
  --format=JobID,JobName,User,Account,Cluster,Partition,State,Reason,Submit,Start,End,Elapsed,AllocCPUS,AllocTRES
```

Result:

```text
JobID  JobName        User    Account     Cluster        Partition  State       Reason             AllocCPUS
9      accounting...  jithin  ai-factory  ai-factory-lab  gpu        CANCELLED+  ReqNodeNotAvail    0
```

### What this proves

Even though the workload never executed, the accounting identity was recorded correctly:

```text
User    = jithin
Account = ai-factory
Cluster = ai-factory-lab
```

The resource fields also correctly show that no resources were allocated:

```text
AllocCPUS = 0
AllocTRES = empty
Elapsed   = 00:00:00
```

This is a **valid accounting-path test**, but not a successful workload-execution test.

A successful execution/accounting test is intentionally deferred until a real compute node exists.

---

# Communication Model

## Administrative plane

```text
SSH :22
Administrator → controller / compute nodes
```

SSH is used for administration, troubleshooting, and configuration. It is not the mechanism by which Slurm schedules jobs.

## Control plane

```text
slurmctld :6817
        ↕
slurmd   :6818
```

This is the scheduler/control communication path.

## Authentication

```text
MUNGE
```

MUNGE provides authentication/trust for Slurm communication.

## Accounting plane

```text
slurmctld :6819 → slurmdbd :6819
slurmdbd  → MariaDB :3306
```

The accounting plane is separate from the workload data path.

## Future workload/data plane

Later phases will add:

```text
GPU ↔ GPU
GPU ↔ NIC
node ↔ node
node ↔ storage
```

including NCCL, InfiniBand, GPUDirect RDMA, NVLink where applicable, and distributed training traffic.

---

# Why Not Put MariaDB Directly Behind Slurmctld?

SlurmDBD is an accounting service layer between Slurm controllers and the database.

The architecture becomes:

```text
Slurm controller
      |
      | Slurm accounting protocol
      v
   SlurmDBD
      |
      | SQL
      v
   MariaDB
```

This provides a dedicated accounting service and allows accounting information from Slurm clusters to be centralized. It also keeps the database implementation behind the SlurmDBD accounting interface rather than making every controller directly manage the accounting database schema/protocol.

---

# Entra ID / Microsoft Production Design

A company using **Microsoft Entra ID** does not need to abandon the Slurm accounting model. The important distinction is between **authentication/identity** and **Slurm resource governance**.

A typical enterprise design might be:

```text
Microsoft Entra ID
       |
       | enterprise identity
       v
Identity / Linux access layer
       |
       | maps user identity/groups
       v
Slurm
       |
       +-- User associations
       |
       +-- Accounts / projects
       |
       +-- QOS / limits
       |
       +-- Partitions
       |
       +-- GPU resources
```

### Does Entra ID replace Slurm users?

No. Entra ID can be the enterprise source of identity, while Slurm still needs a usable Unix identity for workload execution and accounting.

In practice, an enterprise Linux environment may use mechanisms such as SSSD/LDAP/AD integration to make centrally managed identities available on Linux. The exact Entra integration architecture depends on how the company provisions Linux identities, SSH access, groups, UID/GID mappings, and compute-node access.

The important design goal is that the identity seen by Slurm is stable and consistent across the controller and compute nodes.

### Would we have multiple organizations?

Not necessarily.

Do **not** model every Entra organization/group/team as a Slurm `Org` automatically.

Instead, design Slurm accounts around **resource ownership and governance**.

For example:

```text
Entra tenant
└── Groups
    ├── AI-Research
    ├── Computer-Vision
    ├── Platform-Engineering
    └── External-Customer-Acme
```

could map to:

```text
Slurm accounts
├── ai-research
├── computer-vision
├── platform
└── customer-acme
```

Users can then be associated with one or more accounts according to company policy.

For example:

```text
alice
 ├── ai-research
 └── platform

bob
 └── ai-research

carol
 └── computer-vision
```

This is more useful than creating an account for every user.

### Could there be multiple Slurm accounts per user?

Yes. This is common when a person works on multiple projects.

For example:

```text
alice
  ├── research-llm
  └── customer-acme
```

The default account can be one of them, while a job can explicitly select another permitted account.

### Could there be multiple Slurm clusters?

Yes, and this becomes particularly relevant in a larger company.

For example:

```text
                    SlurmDBD / central accounting
                              |
              +---------------+---------------+
              |               |               |
        eu-prod cluster   us-prod cluster   dev cluster
              |               |               |
           GPUs            GPUs            GPUs
```

The accounting database can then provide a central view across clusters.

This is different from creating multiple Entra tenants. A company can have one Entra tenant and multiple Slurm clusters.

---

# Production Example: GPU Quota Model

Suppose a company has:

```text
Entra users:
  Alice
  Bob
  Carol

Projects:
  LLM Research
  Computer Vision
```

A possible Slurm model is:

```text
Account: llm-research
  Alice
  Bob
  GPU quota: 32

Account: computer-vision
  Carol
  GPU quota: 16
```

Then Slurm accounting can answer:

```text
How many GPUs did llm-research consume this month?
Which user consumed them?
How much GPU time was used?
Did the project exceed its quota?
Which cluster supplied the resources?
```

This is the bridge between **enterprise identity** and **AI infrastructure resource governance**.

The identity system says:

> Alice is Alice and belongs to these enterprise groups.

The Slurm policy says:

> Alice may submit workloads to these projects and may consume these resources under these limits.

That separation is extremely important in a production AI factory.

---

# Phase 02 Troubleshooting Notes

## `sacctmgr` says unsupported accounting_storage plugin

Observed before configuring `slurmctld`:

```text
You are not running a supported accounting_storage plugin
Only 'accounting_storage/slurmdbd' is supported.
```

Cause:

```text
AccountingStorageType = (null)
```

Resolution:

```ini
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
AccountingStoragePort=6819
```

and restart `slurmctld`.

## `slurmctld` reports port 6817 already in use

Observed when manually starting a second controller instance:

```text
Error binding slurm stream socket: Address already in use
```

Cause: the systemd-managed `slurmctld` was already running.

Resolution:

```bash
systemctl restart slurmctld
scontrol ping
```

Do not start a second controller instance on the same port.

## `slurmctld -t` produced a bind error

In this environment, the command attempted to initialize/bind the controller rather than behaving as a harmless configuration-only test.

Resolution: validate through the running daemon and `scontrol show config` instead.

## SlurmDBD database tuning warnings

Warnings about recommended InnoDB values did not prevent operation. They are recorded for future production tuning work rather than changing database settings prematurely in this learning phase.

---

# Phase 02 Final State

```text
slurm-controller-01
│
├── MUNGE                       ✅
│
├── slurmctld :6817             ✅
│      │
│      │ accounting RPC :6819
│      ▼
├── slurmdbd :6819              ✅
│      │
│      │ SQL :3306
│      ▼
└── MariaDB
       └── slurm_acct_db         ✅
            ├── cluster
            ├── account
            ├── user
            ├── association
            ├── QOS
            └── job accounting tables
```

Accounting identity is established as:

```text
ai-factory-lab
└── ai-factory
    └── jithin
```

The normal accounting path has been validated with a real job submission, even though the job could not execute because no compute node exists.

---

# Phase 02 Completion Decision

**Phase 02 is complete.**

The SlurmDBD failure/recovery test is intentionally **not part of the Phase 02 completion gate anymore**.

It will be performed in a future lab when a real compute node and real workload are available. The test should then observe actual behavior rather than assume it.

Future failure test should cover:

```text
1. Real compute node available
2. Real job running / being accounted
3. Stop or isolate SlurmDBD
4. Observe slurmctld behavior
5. Observe accounting persistence/caching behavior
6. Restore SlurmDBD
7. Verify recovery and accounting consistency
```

---

# Rebuild / Reproduction Notes

Persistent/cheap components to retain:

```text
MariaDB database
slurm_acct_db
slurmdbd configuration
slurm.conf accounting settings
```

Expensive GPU compute should remain disposable and be rebuilt in later phases.

Before recreating compute nodes, preserve the accounting/control-plane configuration so that new nodes can be onboarded without rebuilding the accounting database.

A future automation script should reproduce:

```text
MariaDB
  → database/user
  → SlurmDBD
  → slurmdbd.conf
  → slurmctld accounting configuration
  → cluster/account/user associations
```

without embedding credentials in Git.

---

# Deferred Study Topics

- SlurmDBD outage behavior and recovery.
- Accounting data buffering/caching during SlurmDBD outage.
- `AccountingStorageEnforce` modes.
- QOS and fair-share.
- Account/user/project GPU quotas.
- JobAcctGather and detailed resource usage.
- GPU TRES accounting.
- Energy accounting.
- Multiple Slurm clusters feeding one SlurmDBD.
- Slurm federation.
- Enterprise identity integration using Entra ID/SSSD and stable UID/GID mapping.
- Service accounts and non-human workloads.
- Chargeback/showback architecture.

These topics should be explored with real infrastructure when they become part of the lab progression.

---

# Phase 03 Boundary

Phase 03 will focus on **Ansible architecture and automation**.

The intended progression remains:

```text
Phase 01  Manual single GPU node foundation       ✅
Phase 02  Accounting / SlurmDBD                   ✅
Phase 03  Ansible architecture                    →
Phase 04  Fresh L40S nodes                        →
Phase 05  Ansible GPU-node onboarding             →
Phase 06  Two-node cluster validation             →
Phase 07  Real distributed GPU workload           →
Phase 08  Dataset + checkpointing                 →
Phase 09  NCCL/network/performance/failures       →
Phase 10  Rebuild/destroy/recreate automation     →
```
