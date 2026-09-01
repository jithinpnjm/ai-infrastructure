#!/usr/bin/env bash
set -u

# Lab 01 host evidence collector.
# Usage:
#   sudo ./collect-host-baseline.sh once [output_dir]
#   sudo ./collect-host-baseline.sh live [output_dir] [interval_seconds]
#
# Designed to work on both controller and GPU nodes. GPU/RDMA commands are
# collected when available; missing commands are recorded rather than fatal.

MODE="${1:-once}"
OUT_BASE="${2:-./evidence}"
INTERVAL="${3:-10}"
HOST="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${OUT_BASE}/${HOST}/${TIMESTAMP}"

mkdir -p "$OUT_DIR"

run() {
  local name="$1"; shift
  {
    echo "### command: $*"
    echo "### timestamp_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    if command -v "$1" >/dev/null 2>&1 || [[ "$1" == /* ]]; then
      "$@"
    else
      echo "COMMAND_NOT_AVAILABLE: $1"
    fi
  } >"${OUT_DIR}/${name}.txt" 2>&1 || true
}

snapshot() {
  local dir="$1"
  mkdir -p "$dir"

  run_to() {
    local name="$1"; shift
    {
      echo "### command: $*"
      echo "### timestamp_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo
      if command -v "$1" >/dev/null 2>&1; then
        "$@"
      else
        echo "COMMAND_NOT_AVAILABLE: $1"
      fi
    } >"${dir}/${name}.txt" 2>&1 || true
  }

  run_to host "hostnamectl"
  run_to os "bash" -c 'cat /etc/os-release'
  run_to kernel "uname" -a
  run_to uptime "uptime"
  run_to cpu "lscpu"
  run_to memory "free" -h
  run_to disks "lsblk" -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,MOUNTPOINTS
  run_to mounts "findmnt"
  run_to pci "lspci" -nn
  run_to numa "numactl" --hardware
  run_to numastat "numastat"
  run_to ip_addr "ip" -br addr
  run_to ip_link "ip" -br link
  run_to ip_route "ip" route
  run_to sockets "ss" -s
  run_to dns "bash" -c 'resolvectl status 2>/dev/null || cat /etc/resolv.conf'
  run_to time_sync "bash" -c 'timedatectl; echo; timedatectl timesync-status 2>/dev/null || true'
  run_to vmstat "vmstat" 1 5
  run_to psi_cpu "bash" -c 'cat /proc/pressure/cpu 2>/dev/null || true'
  run_to psi_memory "bash" -c 'cat /proc/pressure/memory 2>/dev/null || true'
  run_to psi_io "bash" -c 'cat /proc/pressure/io 2>/dev/null || true'
  run_to iostat "iostat" -xz 1 5
  run_to ethtool "bash" -c 'for n in /sys/class/net/*; do n=${n##*/}; echo "===== $n ====="; ethtool "$n" 2>&1 || true; done'
  run_to slurm_version "bash" -c 'scontrol version 2>/dev/null || true; slurmd -V 2>/dev/null || true; slurmctld -V 2>/dev/null || true'
  run_to slurm_config "bash" -c 'scontrol show config 2>/dev/null || true'
  run_to slurm_nodes "bash" -c 'sinfo -N -l 2>/dev/null || true; echo; scontrol show nodes 2>/dev/null || true'
  run_to systemd_slurm "bash" -c 'systemctl --no-pager --full status munge slurmctld slurmd 2>/dev/null || true'
  run_to nvidia_smi "nvidia-smi"
  run_to nvidia_smi_L "nvidia-smi" -L
  run_to nvidia_topology "nvidia-smi" topo -m
  run_to nvidia_dmon "bash" -c 'nvidia-smi dmon -s pucvmet -c 5 2>/dev/null || true'
  run_to gpu_processes "nvidia-smi" pmon -c 5
  run_to rdma_link "rdma" link
  run_to ibstat "ibstat"
  run_to ibdev2netdev "ibdev2netdev"
  run_to mounts_df "df" -hT
  run_to journal_errors "bash" -c 'journalctl -p warning..alert -b --no-pager 2>/dev/null | tail -n 300'

  {
    echo "host=${HOST}"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "kernel=$(uname -r)"
    echo "uptime=$(uptime -p 2>/dev/null || true)"
  } >"${dir}/SUMMARY.txt"
}

if [[ "$MODE" == "once" ]]; then
  snapshot "$OUT_DIR"
  echo "Evidence collected: $OUT_DIR"
elif [[ "$MODE" == "live" ]]; then
  echo "Live collection started: $OUT_DIR"
  echo "Interval: ${INTERVAL}s"
  echo "Press Ctrl-C to stop."
  trap 'echo; echo "Live collection stopped: $OUT_DIR"; exit 0' INT TERM
  i=0
  while true; do
    i=$((i + 1))
    snapshot "${OUT_DIR}/sample-$(printf '%05d' "$i")"
    sleep "$INTERVAL"
  done
else
  echo "Usage: $0 {once|live} [output_dir] [interval_seconds]" >&2
  exit 2
fi
