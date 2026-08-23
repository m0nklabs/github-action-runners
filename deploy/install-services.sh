#!/usr/bin/env bash
#
# install-services.sh — genereer + start een systemd-unit per runner.
# De unit-naam volgt de standaard GitHub-conventie: actions.runner.<org>.<name>.
# Gebruik: sudo ./deploy/install-services.sh   (of ./install-all.sh als root)
set -euo pipefail

ORG="m0nklabs"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER="flip"

if [[ $(id -u) -ne 0 ]]; then
  echo "Dit script moet met sudo/root draaien." >&2
  exit 1
fi

for i in 1 2 3 4; do
  DIR="${BASE_DIR}/actions-runner-${i}"
  echo "=== systemd-unit voor m0nklabs-runner-${i} ==="
  ( cd "${DIR}" && ./svc.sh install "${USER}" )
  # Corrigeer het runner-`.path` naar een compleet, generiek PATH. config.sh
  # schrijft een minimaal PATH zonder /usr/local/bin, waardoor geïnstalleerde
  # tools (gitleaks, go, e.d.) onzichtbaar zijn in job-stappen. Zie README.
  FULL_PATH="/home/flip/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/go/bin:/usr/local/bin:/home/flip/.local/bin:/home/flip/.cargo/bin:/home/flip/.local/share/pnpm:/usr/bin:/bin"
  echo "${FULL_PATH}" > "${DIR}/.path"
  echo "  -> .path gezet op compleet generiek PATH"
done

# GPU-drop-in voor ALLE runners: elke runner kan GPU-werk doen (één machine,
# zelfde GPU's/tools). Via per-project env bepaalt een job of hij de GPU inzet.
# PATH hier is consistent met het `.path`-bestand hierboven (venvs/gpu voorop).
for i in 1 2 3 4; do
  DROP="/etc/systemd/system/actions.runner.${ORG}.m0nklabs-runner-${i}.service.d"
  mkdir -p "${DROP}"
  cat > "${DROP}/90-gpu.conf" <<EOF
[Service]
Environment="PATH=/home/flip/venvs/gpu/bin:/home/flip/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/go/bin:/usr/local/bin:/home/flip/.local/bin:/home/flip/.cargo/bin:/home/flip/.local/share/pnpm:/usr/bin:/bin"
Environment="GOPATH=/home/flip/go"
Environment="GOROOT=/usr/local/go"
Environment="VIRTUAL_ENV=/home/flip/venvs/gpu"
Environment="CUDA_VISIBLE_DEVICES=0,1"
EOF
  echo "GPU-drop-in geschreven: ${DROP}/90-gpu.conf"
done

systemctl daemon-reload
echo "Klaar. Start de services met: sudo systemctl start actions.runner.${ORG}.m0nklabs-runner-{1..4}.service"
