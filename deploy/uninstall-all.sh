#!/usr/bin/env bash
#
# uninstall-all.sh — stop en verwijder de systemd-units + de-registreer de runners.
# VOORZICHTIG: dit ontkoppelt de runners bij GitHub en stopt de services.
# Gebruik alleen wanneer je de pool echt wil verwijderen/opnieuw opbouwen.
set -euo pipefail

ORG="m0nklabs"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $(id -u) -ne 0 ]]; then
  echo "Dit script moet met sudo/root draaien." >&2
  exit 1
fi

# 1) stop + disable services
for i in 1 2 3 4; do
  SVC="actions.runner.${ORG}.m0nklabs-runner-${i}.service"
  systemctl stop "${SVC}" 2>/dev/null || true
  systemctl disable "${SVC}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SVC}" "/etc/systemd/system/multi-user.target.wants/${SVC}"
  rm -rf "/etc/systemd/system/${SVC}.d"
  echo "service ${SVC} gestopt en verwijderd"
done
systemctl daemon-reload

# 2) de-registreer bij GitHub (reg-token nodig via gh)
if command -v gh >/dev/null 2>&1; then
  echo "De-registreer runners bij GitHub (via gh) ..."
  for i in 1 2 3 4; do
    NAME="m0nklabs-runner-${i}"
    RUNNER_ID=$(gh api "/orgs/${ORG}/actions/runners" --jq ".runners[] | select(.name==\"${NAME}\") | .id" | head -1)
    if [[ -n "${RUNNER_ID}" ]]; then
      # verwijder via de runner-map (nodig voor een geldig removal-token)
      ( cd "${BASE_DIR}/actions-runner-${i}" && ./config.sh remove --token "$(gh api -X POST /orgs/${ORG}/actions/runners/remove-token --jq .token)" ) || true
      echo "runner ${NAME} (id ${RUNNER_ID}) de-geregistreerd"
    fi
  done
else
  echo "gh niet gevonden — de-registratie overslaan (doe dit handmatig)."
fi

echo "Klaar."
