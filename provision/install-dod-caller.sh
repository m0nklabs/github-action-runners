#!/usr/bin/env bash
# Installeert de vaste dod-check caller in één repo, of in alle repo's die in het
# MoniFuse-registry een DoD hebben. De caller bevat BEWUST geen instellingen —
# of de check draait, in welke modus, met welke timeout en of rood blokkeert staat
# centraal in het registry. Dit bestand verandert daardoor nooit meer, en uitrollen
# is idempotent.
#
# Gebruik:
#   ./provision/install-dod-caller.sh m0nklabs/monifuse
#   ./provision/install-dod-caller.sh --all
#   ./provision/install-dod-caller.sh --all --dry-run
#
# Vereist: gh (geauthenticeerd met repo- en workflow-scope) en netwerk naar MoniFuse.
set -euo pipefail

MONIFUSE_URL="${MONIFUSE_URL:-http://127.0.0.1:7994}"
CALLER_PATH=".github/workflows/dod.yml"
DRY_RUN=false
ALL=false
REPOS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) REPOS+=("$1") ;;
  esac
  shift
done

if ! $ALL && [ ${#REPOS[@]} -eq 0 ]; then
  echo "gebruik: $0 <owner/repo> [owner/repo ...] | --all [--dry-run]" >&2
  exit 2
fi

caller_body() {
  cat <<'YAML'
## Caller: laat de gedeelde dod-check de Definition of Done van dit project op de PR zetten.
#
# Er staat bewust GEEN `with:`-blok. Alle instellingen (of de check draait, in
# welke modus, met welke timeout, of rood de merge blokkeert) staan centraal in
# het MoniFuse-registry. Dit bestand is een dode letter: het verandert nooit meer.
#
# `pull-requests: write` is verplicht: zonder die permissie kan de reusable
# workflow het resultaat niet als PR-commentaar plaatsen.
name: Definition of Done

on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: dod-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  dod:
    uses: m0nklabs/github-action-runners/.github/workflows/dod-check.yml@main
    secrets: inherit
YAML
}

policy_field() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

registry_repos() {
  curl -sS -m 20 "${MONIFUSE_URL}/api/registry" | python3 -c '
import json, sys
reg = json.load(sys.stdin)
for project in reg.get("projects", []):
    status = (project.get("status") or "").lower()
    if status in ("vendored", "archived"):
        continue
    if not (project.get("dod_command") or "").strip():
        continue
    for repo in project.get("repos") or []:
        name = repo.get("name") if isinstance(repo, dict) else str(repo)
        if name and "/" in name:
            print(name)
'
}

install_one() {
  local repo="$1"
  local policy code enabled reason branch sha tmp

  policy="$(mktemp)"
  code="$(curl -sS -m 20 -o "$policy" -w '%{http_code}' \
    "${MONIFUSE_URL}/api/portfolio/ci?repo=${repo}" || echo 000)"
  if [ "$code" = "404" ]; then
    echo "  OVERGESLAGEN: niet in het MoniFuse-registry"
    rm -f "$policy"; return 0
  fi
  if [ "$code" != "200" ]; then
    echo "  FOUT: MoniFuse gaf HTTP ${code}"
    rm -f "$policy"; return 1
  fi

  enabled="$(policy_field "$policy" enabled)"
  reason="$(policy_field "$policy" reason)"
  rm -f "$policy"
  if [ "${enabled,,}" != "true" ]; then
    echo "  OVERGESLAGEN: ci staat uit in het registry (${reason})"
    return 0
  fi

  branch="$(gh api "/repos/${repo}" --jq '.default_branch' 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    echo "  FOUT: repo niet bereikbaar met gh"
    return 1
  fi

  sha="$(gh api "/repos/${repo}/contents/${CALLER_PATH}?ref=${branch}" --jq '.sha' 2>/dev/null || true)"

  if $DRY_RUN; then
    if [ -n "$sha" ]; then
      echo "  ZOU BIJWERKEN ${CALLER_PATH} (bestaat al op ${branch})"
    else
      echo "  ZOU PLAATSEN  ${CALLER_PATH} op ${branch}"
    fi
    return 0
  fi

  tmp="$(mktemp)"
  caller_body > "$tmp"
  local sha_args=()
  [ -n "$sha" ] && sha_args=(-f "sha=${sha}")

  gh api -X PUT "/repos/${repo}/contents/${CALLER_PATH}" \
    -f "message=ci(dod): install the shared Definition of Done caller (settings live in MoniFuse)" \
    -f "branch=${branch}" \
    -f "content=$(base64 -w0 < "$tmp")" \
    "${sha_args[@]}" > /dev/null
  rm -f "$tmp"

  if [ -n "$sha" ]; then
    echo "  BIJGEWERKT ${CALLER_PATH}"
  else
    echo "  GEPLAATST  ${CALLER_PATH}"
  fi
}

if $ALL; then
  mapfile -t REPOS < <(registry_repos | sort -u)
  echo "repo's met een DoD in het registry: ${#REPOS[@]}"
fi

failures=0
for repo in "${REPOS[@]}"; do
  echo "== ${repo}"
  install_one "$repo" || failures=$((failures + 1))
done

echo
$DRY_RUN && echo "dry-run: er is niets geschreven"
echo "klaar: ${#REPOS[@]} repo('s) bekeken, ${failures} fout"
[ "$failures" -eq 0 ]
