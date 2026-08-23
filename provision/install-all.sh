#!/usr/bin/env bash
#
# install-all.sh — installeer & configureer alle centrale runners, + systemd.
# Wordt vanuit de eerder neergezette structuur gedraaid (zie README).
set -euo pipefail

BASE_DIR="/home/flip/github-action-runners"
cd "${BASE_DIR}"

# 1) registreer 4 org-level runners; runner-1 en runner-2 zijn GPU-capabel
./provision/install-runner.sh 1 --gpu
./provision/install-runner.sh 2 --gpu
./provision/install-runner.sh 3
./provision/install-runner.sh 4

# 2) leg de gemeenschappelijke env in elke runner-installatie
for i in 1 2 3 4; do
  cp env/common.github-action-runner.env "${BASE_DIR}/actions-runner-${i}/.env"
done

# 3) systemd-units genereren en starten
./deploy/install-services.sh

echo "Alle 4 runners geconfigureerd."
