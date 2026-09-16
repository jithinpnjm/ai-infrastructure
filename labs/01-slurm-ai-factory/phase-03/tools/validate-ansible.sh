#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/ansible"

required_files=(
  "ansible.cfg"
  "requirements.yml"
  "inventories/lab/hosts.yml"
  "inventories/lab/group_vars/all.yml"
  "inventories/lab/group_vars/gpu_workers.yml"
  "playbooks/gpu-node.yml"
  "playbooks/validate-gpu-node.yml"
  "roles/base/tasks/main.yml"
  "roles/nvidia/tasks/main.yml"
  "roles/munge/tasks/main.yml"
  "roles/slurm/tasks/main.yml"
  "roles/validation/tasks/main.yml"
  "roles/slurm/templates/slurm.conf.j2"
  "roles/slurm/templates/gres.conf.j2"
  "roles/slurm/templates/cgroup.conf.j2"
)

printf 'Checking Phase 03 Ansible tree...\n'
for file in "${required_files[@]}"; do
  test -f "${ANSIBLE_DIR}/${file}" || {
    echo "MISSING: ${file}" >&2
    exit 1
  }
done

echo 'Required files: OK'

if command -v ansible-playbook >/dev/null 2>&1; then
  echo 'Running Ansible syntax checks...'
  cd "${ANSIBLE_DIR}"
  ansible-playbook --syntax-check playbooks/gpu-node.yml
  ansible-playbook --syntax-check playbooks/validate-gpu-node.yml
  echo 'Ansible syntax: OK'
else
  echo 'ansible-playbook not installed; structural validation completed only.'
  echo 'Install Ansible and run this script again for syntax validation.'
fi

echo 'Phase 03 Ansible static validation complete.'
