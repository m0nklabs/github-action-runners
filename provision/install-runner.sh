#!/usr/bin/env bash
#
# Install-runner.sh — registreer een self-hosted runner bij GitHub (org-level).
#
# Gebruik (org-scope, "default pool"):
#   ./install-runner.sh <nummer> [--no-gpu]
#
# Voorbeelden:
#   ./install-runner.sh 1            # registreer m0nklabs-runner-1 (standaard gpu)
#   ./install-runner.sh 1 --no-gpu   # registreer m0nklabs-runner-1 zonder gpu-label
#
# Vereisten:
#   - gh CLI geauthenticeerd met een token met admin:org scope
#   - actieve registratie-token (wordt opgehaald via gh api)
#
# Labels:
#   - basislabels (automatisch): self-hosted, Linux, X64
#   - label "gpu" -> standaard op ELKE runner: alle runners kunnen GPU-werk doen
#     (één machine, zelfde GPU's/tools). Via per-project env bepaalt een job of
#     hij de GPU inzet. Gebruik --no-gpu om af te wijken.
#
# De pool is ORG-LEVEL: runners werken voor ALLE projecten in de org (en op
# verzoek ook voor privé-accounts). Er is dus GEEN per-project runner nodig.
set -euo pipefail

ORG="m0nklabs"
BASE_DIR="/home/flip/github-action-runners"
NUM="${1:?geef runner-nummer (1..4)}"
GPU="--labels gpu"
if [[ "${2:-}" == "--no-gpu" ]]; then GPU=""; fi

RUNNER_DIR="${BASE_DIR}/actions-runner-${NUM}"
NAME="m0nklabs-runner-${NUM}"

if [[ ! -x "${RUNNER_DIR}/config.sh" ]]; then
  echo "Fout: ${RUNNER_DIR}/config.sh ontbreekt — eerst de structuur uitpakken." >&2
  exit 1
fi

# --- registratie-token (org-level) ---
REGO_URL="/orgs/${ORG}/actions/runners/registration-token"
TOKEN="$(gh api -X POST "${REGO_URL}" --jq .token)"
if [[ -z "${TOKEN}" ]]; then
  echo "Fout: kon geen registratie-token ophalen voor org ${ORG}." >&2
  exit 1
fi

echo "Registreer org-runner '${NAME}' (dir: ${RUNNER_DIR}) GPU=${GPU:-nee} ..."
cd "${RUNNER_DIR}"
./config.sh \
  --url "https://github.com/${ORG}" \
  --token "${TOKEN}" \
  --name "${NAME}" \
  --work "_work" \
  --unattended \
  --replace \
  ${GPU}

echo "Klaar. Runner '${NAME}' is geregistreerd als org-runner."
