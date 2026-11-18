# Self-Hosted GitHub Actions Runners (centraal)

Centrale pool van **self-hosted GitHub Actions runners** voor de
`m0nklabs`-organisatie op host **`ai-kvm2`** (24 CPU, 108 GB RAM, 2× NVIDIA GPU:
RTX 3060 + RTX 5060 Ti).

> **Principe:** runners zijn **org-level** — ze bedienen **álle** projecten in de
> org (en op verzoek ook privé-accounts). Er is dus **nooit één runner per
> project** meer. Project-specifieke omgeving wordt per project aangeleverd via
> een env-bestand (zie hieronder), niet door aparte runners te draaien.

> **Uitzondering — `m0nk111` repo-level runners (PR-Piet).** Het user-account
> `m0nk111` is géén org, en GitHub biedt géén account-level runner-pools — dus
> voor de `m0nk111/<repo>`-repos zijn **repo-level** runners de enige optie.
> Deze staan onder `/home/flip/github-action-runners-m0nk111/run-<repo>` (naam
> `m0nk111-<repo>-runner`, labels `self-hosted, Linux`, systemd-unit
> `actions.runner.m0nk111-<repo>.m0nk111-<repo>-runner.service`), elk met een
> repo-secret `GUARDIAN_API_KEY` (de pr-piet gateway key). Ze draaien PR-Piet
> (single-call review). Dit is de enige uitzondering op het org-level-principe;
> dit werd bewust gedaan op verzoek (2026-08-27) en moet niet voor andere
> accounts/repos gekopieerd worden zonder expliciete aanleiding.

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

## Generieke, taal-specifieke workflows (reusable)

Om wildgroei én kwaliteitsverschil per project tegen te gaan, levert deze repo
**herbruikbare (reusable) workflows** per programmeertaal. Een project draait
**alleen de workflows voor de talen die het werkelijk bevat** — geen overbodige
checks voor andere talen.

> De centrale repo is **publiek**: projecten kunnen de reusable workflows
> cross-repo aanroepen met `uses: m0nklabs/github-action-runners/...@main`
> (cross-repo reusable werkt niet vanuit een privé-repo).

Beschikbare reusable workflows (in `.github/workflows/`):

| Workflow | Taal | Doet |
|----------|------|------|
| `python-ci.yml` | Python | ruff lint + pytest (**strict**; `allow-test-failures: true` = fail-open) |
| `frontend-ci.yml` | JavaScript + TypeScript | npm ci + test + build — **één workflow dekt beide** (JS én TS); zet `source-dir` op de map met de `package.json` (default `src/frontend`) |
| `go-ci.yml` | Go | vet + test + build |
| `rust-ci.yml` | Rust | fmt + clippy + test |
| `c-cpp-ci.yml` | C/C++ | CMake build + ctest |
| `csharp-ci.yml` | C#/.NET | dotnet restore + build + test |
| `java-ci.yml` | Java/Kotlin | Gradle/Maven build + test |
| `ruby-ci.yml` | Ruby | bundle install + test |
| `swift-ci.yml` | Swift | swift build + test |
| `gpu-ci.yml` | (GPU) | GPU-tests, serieel via `gpu-run.sh` |
| `codeql-ci.yml` | (CodeQL) | SAST security-scan per taal — **gratis op publieke repos** (`c-cpp`, `csharp`, `go`, `java-kotlin`, `javascript-typescript`, `python`, `ruby`, `swift`) |
| `semgrep-ci.yml` | (SAST) | **Private/public SAST** via one digest-pinned Semgrep OSS scan. Defaults: `config: p/default`, report-only findings; SARIF + coverage JSON as ordinary Actions artifacts, not Code Scanning. See [Semgrep contract](#semgrep-contract-and-rollout). |
| `dod-check.yml` | (proces) | **Definition of Done uit het MoniFuse-registry** uitvoeren (`mode: run`) of de laatste uitslag ophalen (`mode: report`), en die als PR-commentaar plaatsen; rode DoD laat de check falen. Caller moet `permissions: pull-requests: write` zetten. De admin-token komt lokaal van de runner (`~/.secrets/monifuse-admin.token`), nooit uit GitHub. |
| `codeql-detect.yml` | (CodeQL auto) | CodeQL met **automatische taal-detectie** (via GitHub languages API, met percentages) — geen handmatige `languages`-input |

### CodeQL met automatische taal-detectie

De eenvoudigste CodeQL-setup: projecten hoeven de talen niet zelf op te geven.
`codeql-detect.yml` vraagt de **GitHub languages API** op en laat in het
linguist-taalportret (met **percentages**) zien welke talen de repo bevat, en
draait CodeQL alleen voor de talen die het project werkelijk heeft.

```yaml
jobs:
  codeql:
    uses: m0nklabs/github-action-runners/.github/workflows/codeql-detect.yml@main
    with:
      min-percent: 1   # optioneel: sla talen onder 1% over
    secrets: inherit
```

> ⚠️ **Belangrijk:** de caller van een CodeQL-workflow (zowel `codeql-detect.yml`
> als `codeql-ci.yml`) moet zelf `permissions: security-events: write`
> declareren. Zonder die write-permission weigert GitHub de reusable te starten
> met `startup_failure` (0 jobs, geen log). Zet bovenaan de workflow:
>
> ```yaml
> permissions:
>   actions: read
>   contents: read
>   security-events: write
> ```
>
> Dit is nodig op **publieke** repos (gratis code-scanning). Op **privé**-repos
> vereist code-scanning betaald Advanced Security; `codeql-detect.yml` detecteert
> dat en slaat automatisch over (`languages=[]`) wanneer de repo privé is.

Lokaal hetzelfde inzicht per repo:

```bash
./bin/detect-languages.sh m0nklabs/oelala         # alle talen + %
./bin/detect-languages.sh --codeql m0nklabs/oelala # alleen CodeQL-talen
```

**Hoe een project de juiste talen aanroept** (bijv. een Python + Node project):

> **JavaScript + TypeScript** worden door **één** workflow gedekt
> (`frontend-ci.yml`) en door CodeQL als één taal
> (`javascript-typescript`). Stel `source-dir` van `frontend-ci` in op de map
> met de `package.json` — de default is `src/frontend`. Semgrep (`config: auto`)
> scant `.js`- en `.ts`-bestanden automatisch mee.

```yaml
name: CI

on:
  push: { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  python:
    uses: m0nklabs/github-action-runners/.github/workflows/python-ci.yml@main
    secrets: inherit
  frontend:
    uses: m0nklabs/github-action-runners/.github/workflows/frontend-ci.yml@main
    with:
      source-dir: src/frontend
    secrets: inherit
  codeql:
    uses: m0nklabs/github-action-runners/.github/workflows/codeql-ci.yml@main
    with:
      languages: '["python", "javascript-typescript"]'
    secrets: inherit
```

- Alleen de nodige `uses:`-regels opnemen → een puur Rust-project zet enkel
  `rust-ci.yml`, nooit `python-ci.yml`.
- Elke workflow heeft `inputs` (zie het bestand) om paden, versies en
  opties per project te sturen. **Geen** overbodige taal-checks voor projecten
  die die taal niet hebben.
- Voorbeelden in `examples/`: `ci.example.yml` (CI), `ci-all.example.yml`
  (CI voor álle talen), `codeql.example.yml` (CodeQL met handmatige talen) en
  `codeql-detect.example.yml` (CodeQL met automatische taal-detectie).

### Gratis CI voor elke taal — privé en publiek

Alle `*-ci.yml`-workflows (Python, Node, Go, Rust, C/C++, C#, Java/Kotlin,
Ruby, Swift) zijn **vrij te gebruiken op élke repo, publiek én privé** — ze
draaien op de centrale self-hosted pool met open-source tools en hebben geen
GitHub-licentie nodig.

**CodeQL (SAST) verschilt hierin:** voor code-scanning was de CodeQL-software
gratis op **publieke** repos. Op **privé**-repos is CodeQL alleen toegestaan
met betaald Advanced Security (de CodeQL Terms verbieden gebruik op niet-
open-source-codebases zonder die licentie). Daarom:
- Publieke repos → draaien `codeql-detect.yml`/`codeql-ci.yml` (gratis) en/of
  `semgrep-ci.yml`.
- Private repositories can use **`semgrep-ci.yml`** without GitHub Code Scanning
  entitlement. It runs Semgrep OSS and uploads ordinary Actions artifacts; it
  never calls the Code Scanning API. Runner access and any hosted Actions
  minutes are separate requirements, not granted by calling a public workflow.

### Semgrep contract and rollout

See [`examples/semgrep.example.yml`](examples/semgrep.example.yml) for triggers,
weekly scheduling, fork policy and permissions. The reusable workflow declares
only `contents: read`, requires no secrets, disables persisted checkout
credentials, and does not install dependencies or execute target-repository
scripts. Both Python helpers are inline in the reusable workflow and run with
`python3 -I`; they are not loaded from the caller's checkout. The scanner gets a
read-only checkout mount, no Docker socket, no inherited token, and a fresh
runner-owned report directory per run attempt. No GPU is used.

| Input | Default | Contract |
| --- | --- | --- |
| `config` | `p/default` | One or more space-separated Semgrep configs; quote paths with spaces. Each becomes a literal `--config` argument, without shell evaluation. Local paths resolve from `src-dir`. `auto`, registry IDs, URLs and local rule files remain supported by the scanner. |
| `src-dir` | `.` | Existing directory inside the checkout. Absolute paths and symlink/path escapes are rejected. The scan and both reports use this same scope. |
| `fail-on` | `none` | `error` blocks unsuppressed ERROR findings; `warning` blocks WARNING + ERROR; `none` disables **only the finding threshold**. Invalid values and all scanner/config/runtime/report/coverage failures are always red. |
| `runs-on` | `["self-hosted", "Linux", "X64"]` | JSON runner labels evaluated with `fromJSON`. Select only runners accessible to the caller. No runner registration is performed. |
| `timeout-minutes` | `20` | Job timeout; includes image retrieval and scanning. |
| `scan-jobs` | `2` | CPU scanner workers, integer 1–16. |

**Initial rollout policy (operator decision, 2026-11-18):** report findings
first, then remediate product issues separately. The default remains
`fail-on: none`: findings are visible in the reports and summary, but do not
block scanner installation. Operational failures are always red. Repositories
can explicitly select `error` or `warning` after their findings are triaged.

**Behavior changes:** the default ruleset is explicitly `p/default` rather
than `auto`. The unused `output-format` input has been removed: output is
always SARIF plus JSON. Remove that input from any older caller rather than
expecting it to change output. `config`, `src-dir` and `fail-on` remain
supported. Existing `fail-on: none` callers cannot mask scanner failures.
Initial rollout callers should explicitly use `fail-on: none` and omit
`secrets: inherit`.

The single scan uses Semgrep OSS **1.184.0**, pinned to the same Docker digest as
`m0nklabs/lastsync`. It emits `semgrep.sarif` and `semgrep.json` together, uploaded
as `semgrep-report` (30-day retention). A gate reads **that exact SARIF**, across
all runs, honoring result-level severity before rule defaults and existing
in-source `nosemgrep` suppressions (counted visibly). There is no second scan,
`--error` gate, mutable pip upgrade, or failure-masking step. Strict scanner
diagnostics, missing/malformed reports, unsuccessful invocations, empty rule
sets and zero scanned targets all fail closed, even with `fail-on: none`.

Coverage is **not** a promise to analyze every language or file. The same-run
JSON must contain scanned targets; zero targets (for example, an unsupported
or fully ignored scope with no applicable rules) is explicitly red, not a clean
scan. Generic/regex rules can count an otherwise unsupported-language file as
scanned; that is not language-specific analysis. In a mixed-language repo, a
scanned file count is not proof that every language was covered. Inspect scanner logs,
`paths.scanned`, errors, ignore rules and applicable OSS rules/parsers before
claiming language coverage. File-size limits and exclusions can reduce coverage.
`--strict` treats scanner warnings as failures. Registry rules are live and may
change independently of the pinned engine; the image digest does not pin
`p/default` or other registry configs. Registry rule licenses are separate from
the OSS engine license.

The host needs Docker, Python 3.9+ and registry connectivity. Org runners do not
automatically serve personal repositories. Do not select GitHub-hosted labels
for private repositories without a separate minutes/billing decision, or install
callers that will queue indefinitely without accessible runners. Untrusted fork
PRs require an isolated runner policy; the example skips them explicitly, not as
successful scans. Never use `pull_request_target` to run this checkout.

Pin rollout callers to the reviewed shared commit and verify in a dedicated
sandbox before activation. Do not create test PRs in production repositories.

Local regression checks (stdlib only; helpers extracted verbatim from YAML):

```bash
python3 -m unittest discover -s tests -v
# Optional synthetic integration cases using the pinned image, no project code:
SEMGREP_CONTAINER_TESTS=1 python3 -m unittest discover -s tests -v
# If installed:
actionlint .github/workflows/semgrep-ci.yml examples/semgrep.example.yml
```

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
  (bewaar het token veilig lokaal, niet in deze repo).
- `sudo`-rechten (wachtwoordloos) om systemd-units te installeren.
- Toegang tot `/home/flip` voor de runner-werkdirs.

## Achtergrond / migratie

Voorheen stonden runners verspreid over project-specifieke `scratch/`-bomen
(org-runners + een repo-runner `oelala-gpu` en een nu verwijderde
`oelala-storage-runner`). Deze centrale pool vervangt die: **4 org-level
runners, één plek, één naamgevingsconventie, GPU optioneel per runner.**

---

## PR-Piet op m0nklabs en m0nk111 (2026-08-27)

Alle **49** repos (27 m0nklabs + 22 m0nk111) draaien PR-Piet via
`m0nklabs/pr-piet/.github/workflows/reusable-pr-piet.yml@main` met
`single_call_review: true` (1 modelcall voor review + suggesties via de
pr-agent fork `m0nklabs/pr-agent`).

- **m0nklabs-repos:** draaien op deze org-pool (runners + org-secret
  `GUARDIAN_API_KEY`, visibility=all).
- **m0nk111-repos:** draaien op de repo-level runners in
  `/home/flip/github-action-runners-m0nk111/` met per-repo secret
  `GUARDIAN_API_KEY` (zelfde pr-piet key).
