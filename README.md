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
├── bin/
│   └── gpu-run.sh                     # centrale GPU-lock wrapper (1 GPU-job tegelijk)
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
| 3 | `m0nklabs-runner-3` | `self-hosted, Linux, X64, gpu` | ✅ GPU 0+1 | `actions.runner.m0nklabs.m0nklabs-runner-3.service` |
| 4 | `m0nklabs-runner-4` | `self-hosted, Linux, X64, gpu` | ✅ GPU 0+1 | `actions.runner.m0nklabs.m0nklabs-runner-4.service` |

> **Alle 4 runners zijn GPU-capabel.** Het zijn 4 processen op dezelfde machine
> (`ai-kvm2`) met dezelfde 2 GPU's (RTX 3060 + RTX 5060 Ti) en dezelfde tools —
> GPU-capabel maken kost dus géén extra schijf/hardware. Elke runner heeft het
> `gpu`-label én een systemd-drop-in met GPU-omgeving (`CUDA_VISIBLE_DEVICES=0,1`,
> `venvs/gpu`). **Of** een job de GPU-ability inzet, bepaalt het project via zijn
> per-project env/workflow — niet via aparte runners.

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

**GPU-jobs (serieel, met centrale lock):**
```yaml
jobs:
  train:
    runs-on: [self-hosted, Linux, gpu]
    steps:
      - uses: actions/checkout@v4
      - name: Train
        run: |
          /home/flip/github-action-runners/bin/gpu-run.sh python train.py ...
```

> **GPU loopt SERIEEL (1 tegelijk).** Alle 4 runners delen dezelfde 2 GPU's
> (`CUDA_VISIBLE_DEVICES=0,1`) op dezelfde host. Om te voorkomen dat meerdere
> GPU-jobs tegelijk op dezelfde kaarten concurreren, moet **elke GPU-job zijn
> zware commando's wrappen met `bin/gpu-run.sh`**. Dat pakt een centrale lock
> (`flock` op `.gpu.lock`): als er al een GPU-job bezig is, WACHT de volgende
> netjes tot die klaar is — er draait nooit meer dan 1 GPU-job tegelijk.
>
> ⚠️ Ga bij een GPU-job **altijd** langs `gpu-run.sh`. Anders kunnen twee
> GPU-jobs (op verschillende runners) parallel op dezelfde kaarten terechtkomen.
> Wil je één specifieke kaart, gebruik dan `CUDA_VISIBLE_DEVICES` binnenin.

---

## Per-project omgeving (bij het project)

Project-specifieke tools/omgeving blijven **bij het project** en worden niet
geschaard per runner. Conventie: een bestand `<project>.github-action-runner.env`
in de centrale `env/`-map, maar de *inhoud* wordt toegepast in het project zelf
(bijv. een `env`-blok in de workflow, of door het bestand te sourcen in een
stap).

De `env/`-map bevat:
- `common.github-action-runner.env` — de gedeelde basis die als `.env` in elke
  runner-installatie wordt gelegd.
- `TEMPLATE.github-action-runner.env` — generiek sjabloon om per project te
  kopiëren (venv's, toolchains, GPU, project-variabelen).
- `<project>.github-action-runner.env` — concrete per-project voorbeelden,
  zoals `oelala.github-action-runner.env`.

Voorbeeld: **oelala** (GPU + lokaal venv) zou in zijn workflow zetten:
```yaml
jobs:
  train:
    runs-on: [self-hosted, Linux, gpu]
    steps:
      - uses: actions/checkout@v4
      - name: Train
        env:
          CUDA_VISIBLE_DEVICES: "0"
          PATH: /home/flip/venvs/gpu/bin:${{ runner.os == 'Linux' && env.PATH || env.PATH }}
        run: |
          /home/flip/github-action-runners/bin/gpu-run.sh python train.py ...
```

> Het `gpu`-label staat op **alle** 4 runners, dus een GPU-job kan op elke runner
> landen. Het per-project env-bestand (of workflow-`env`-blok) bepaalt vervolgens
> wát er met de GPU-ability gebeurt.

Geen wildgroei aan runners — alleen project-specificke config wordt per project
meegenomen.

---

## Runner-PATH (belangrijk)

De runner leest het PATH voor job-stappen uit het `.path`-bestand in elke
runner-installatie (`actions-runner-{1..4}/.path`). `config.sh` schrijft daar
standaard alleen `~/.npm-global/bin:...:/usr/bin:/bin` in, waardoor **system-wide
tools in `/usr/local/bin` onzichtbaar zijn** in job-stappen (bv. `gitleaks`,
`go`).

De centrale pool corrigeert dit naar een compleet generiek PATH:

```
/home/flip/.npm-global/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/go/bin:
/usr/local/bin:/home/flip/.local/bin:/home/flip/.cargo/bin:
/home/flip/.local/share/pnpm:/usr/bin:/bin
```

`deploy/install-services.sh` zet dit PATH automatisch in elke runner.
Als een project een tool heeft die buiten dit PATH staat, voeg die dan toe in
het project (via `env/<project>.github-action-runner.env` of de workflow), niet
door runner-specifieke ad-hoc-installaties.

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
# één runner registreren (org-level, standaard gpu-capabel):
./provision/install-runner.sh 1

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
