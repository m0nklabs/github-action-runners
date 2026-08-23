#!/usr/bin/env bash
#
# gpu-run.sh — draai een GPU-commando met een CENTRALE lock, zodat er op de
# hele runner-pool altijd maar 1 GPU-workflow tegelijk draait.
#
# Waarom: alle 4 runners (m0nklabs-runner-1..4) zijn GPU-capabel en delen
# dezelfde 2 GPU's op host `ai-kvm2`. Zonder lock zouden meerdere GPU-jobs
# tegelijk op dezelfde kaarten concurreren. Deze wrapper zorgt dat job #2
# netjes WACHT tot job #1 klaar is.
#
# Gebruik in een (GPU-)workflow-stap:
#   runs-on: [self-hosted, Linux, gpu]
#   steps:
#     - name: Train
#       run: |
#         /home/flip/github-action-runners/bin/gpu-run.sh python train.py ...
#
# ongeldige/achterstallige lock: flock is NFS/FS-veilig op deze host en geeft
# het lock automatisch vrij wanneer het proces eindigt (of sterft).
set -euo pipefail

LOCKFILE="${GPU_LOCKFILE:-/home/flip/github-action-runners/.gpu.lock}"

if [[ $# -eq 0 ]]; then
  echo "Gebruik: $0 <commando...>" >&2
  echo "OF:      $0 -- sh -c '<commando met pipes/beletsel>'" >&2
  exit 1
fi

# flock wacht standaard (blokkerend) tot het lock vrijkomt; daarna draait alleen
# dit proces het commando. Perfect voor '1 tegelijk, rest wacht'.
exec flock "${LOCKFILE}" "$@"
