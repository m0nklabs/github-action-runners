# Self-Hosted GitHub Actions Runners (centraal)

Centrale pool van **self-hosted GitHub Actions runners** voor de
`m0nklabs`-organisatie op host **`ai-kvm2`** (24 CPU, 108 GB RAM, 2× NVIDIA GPU:
RTX 3060 + RTX 5060 Ti).

> **Principe:** runners zijn **org-level** — ze bedienen **álle** projecten in de
> org (en op verzoek ook privé-accounts). Er is dus **nooit één runner per
> project** meer. Project-specifieke omgeving wordt per project aangeleverd via
> een env-bestand (zie hieronder), niet door aparte runners te draaien.

---

## Doelarchitectuur

```
/home/flip/github-action-runners/
├── README.md                          # dit bestand
├── AGENTS.md                          # instructies voor AI-agents/LLM's in deze repo
├── actions-runner-1/                  # runner-installatie (m0nklabs-runner-1)
├── actions-runner-2/                  # runner-installatie (m0nklabs-runner-2)
├── actions-runner-3/                  # runner-installatie (m0nklabs-runner-3)
├── actions-runner-4/                  # runner-installatie (m0nklabs-runner-4)
├── env/
│   ├── common.github-action-runner.env      # gedeelde basis-omgeving (wordt .env in elke runner)
│   └── <project>.github-action-runner.env   # VOORBEELD per-project omgeving
├── provision/
│   ├── install-runner.sh              # registreer één runner bij GitHub (org-level)
│   └── install-all.sh                 # installeer + configureer alles (runner + services)
└── deploy/
    ├── install-services.sh            # systemd-units genereren + starten + GPU drop-ins
    └── uninstall-all.sh               # services stoppen + runners de-registreren
```

## De 4 runners

| Runner | GitHub-naam | Labels | GPU | Launcher service |
|--------|-------------|--------|-----|------------------|
| 1 | `m0nklabs-runner-1` | `self-hosted, Linux, X64, gpu` | ✅ GPU 0+1 | `actions.runner.m0nklabs.m0nklabs-runner-1.service` |
| 2 | `m0nklabs-runner-2` | `self-hosted, Linux, X64, gpu` | ✅ GPU 0+1 | `actions.runner.m0nklabs.m0nklabs-runner-2.service` |
| 3 | `m0nklabs-runner-3` | `self-hosted, Linux, X64` | ❌ | `actions.runner.m0nklabs.m0nklabs-runner-3.service` |
| 4 | `m0nklabs-runner-4` | `self-hosted, Linux, X64` | ❌ | `actions.runner.m0nklabs.m0nklabs-runner-4.service` |

> Runner-1 en runner-2 hebben een extra `gpu`-label **en** een systemd-drop-in
> met GPU-omgeving (`CUDA_VISIBLE_DEVICES=0,1`, `venvs/gpu`). Dat maakt GPU
> **optioneel per runner**: alleen jobs die het `gpu`-label targeten landen op
> een GPU-runner; alle andere jobs verdelen zich over de hele pool.

---

## Hoe projecten de runners gebruiken

Elk project (zoals `m0nklabs/oelala`) kan deze pool gewoon gebruiken met
`runs-on`. Alle 4 runners draaien voor de hele org, dus er hoeft niets per
project geconfigureerd te worden.

**Generieke jobs (geen GPU):**
```yaml
jobs:
  build:
    runs-on: [self-hosted, Linux]
    steps:
      - uses: actions/checkout@v4
```

**GPU-jobs:**
```yaml
jobs:
  train:
    runs-on: [self-hosted, Linux, gpu]
    env:
      CUDA_VISIBLE_DEVICES: "0"
    steps:
      - uses: actions/checkout@v4
```

> **Let op GPU-verdeling:** de twee GPU-runners delen dezelfde 2 GPU's
> (`CUDA_VISIBLE_DEVICES=0,1`). Gebruik in GPU-jobs expliciet `CUDA_VISIBLE_DEVICES`
> naar één device (of laat de job dat zelf doen), anders concurreren twee parallelle
> GPU-jobs om dezelfde GPU's.

---

## Per-project omgeving (bij het project)

Project-specifieke tools/omgeving blijven **bij het project** en worden niet
geschaard per runner. Conventie: een bestand `<project>.github-action-runner.env`
in de centrale `env/`-map, maar de *inhoud* wordt toegepast in het project zelf
(bijv. een `env`-blok in de workflow, of door het bestand te sourcen in een
stap). Zie `env/oelala.github-action-runner.env` als voorbeeld.

Voorbeeld: **oelala** (GPU + lokaal venv) zou in zijn workflow zetten:
```yaml
jobs:
  train:
    runs-on: [self-hosted, Linux, gpu]
    env:
      CUDA_VISIBLE_DEVICES: "0"
      PATH: /home/flip/venvs/gpu/bin:${{ runner.os == 'Linux' && env.PATH || env.PATH }}
```

Geen wildgroei aan runners — alleen project-specificke config wordt per project
meegenomen.

---

## Installatie / herinstallatie (deploy)

```bash
cd /home/flip/github-action-runners

# 1) runner-bundel in de actie dirs uitpakken (zie "Runner-update" hieronder)
# 2) registreer alle runners + start services:
GH_TOKEN=... ./provision/install-all.sh        # (draait sudo intern)
```

Of handmatig:
```bash
# één runner registreren (org-level):
./provision/install-runner.sh 1 --gpu

# services aanmaken + starten:
sudo ./deploy/install-services.sh
sudo systemctl start actions.runner.m0nklabs.m0nklabs-runner-{1..4}.service
```

Verwijderen:
```bash
sudo ./deploy/uninstall-all.sh
```

---

## Management van de draaiende runners

```bash
# status
sudo systemctl status actions.runner.m0nklabs.m0nklabs-runner-1.service

# logs
journalctl -u actions.runner.m0nklabs.m0nklabs-runner-1.service -f

# herstart
sudo systemctl restart actions.runner.m0nklabs.m0nklabs-runner-1.service
```

Bij GitHub (via `gh CLI`):
```bash
gh api /orgs/m0nklabs/actions/runners --jq '.runners[] | "\(.name) \(.status) \(.version) [\([.labels[].name]|join(","))]"'
```

---

## Runner-update (naar een nieuwere actions/runner-versie)

```bash
cd /home/flip/github-action-runners
VER=2.336.0   # pas aan naar de nieuwste release
curl -sSL -o actions-runner-linux-x64-${VER}.tar.gz \
  https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-x64-${VER}.tar.gz

# verifieer checksum tegen de release-notes van actions/runner
sha256sum actions-runner-linux-x64-${VER}.tar.gz

for i in 1 2 3 4; do
  sudo systemctl stop actions.runner.m0nklabs.m0nklabs-runner-${i}.service
  rm -rf actions-runner-${i}/_work/.runner  # werk dir magistral
  tar xzf actions-runner-linux-x64-${VER}.tar.gz -C actions-runner-${i}
  # .env en .path opnieuw naar deze map kopiëren (ze worden overschreven door de cleanup)
  cp env/common.github-action-runner.env actions-runner-${i}/.env
  sudo systemctl start actions.runner.m0nklabs.m0nklabs-runner-${i}.service
done
```

> Na een herinstallatie in dezelfde map moet de runner opnieuw geregistreerd
> worden (config verwijderd). Gebruik dan `./provision/install-runner.sh`.

---

## Voorwaarden / vereisten

- `gh` CLI geauthenticeerd met een token met `admin:org` scope
  (bijv. `~/.secrets/github/m0nk111-admin.token`).
- `sudo`-rechten (wachtwoordloos) om systemd-units te installeren.
- Toegang tot `/home/flip` voor de runner-werkdirs.

## Achtergrond / migratie

Voorheen stonden runners verspreid over project-specifieke `scratch/`-bomen
(org-runners + een repo-runner `oelala-gpu` en een nu verwijderde
`oelala-storage-runner`). Deze centrale pool vervangt die: **4 org-level
runners, één plek, één naamgevingsconventie, GPU optioneel per runner.**
