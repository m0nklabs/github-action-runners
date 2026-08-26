# AGENTS.md — instructies voor AI-agents in deze repo

Dit bestand beschrijft hoe je als agent veilig met deze self-hosted runner-pool
mag omgaan. Lees het VOORDAT je iets wijzigt aan runners, services of de repo.

## Wat dit is

Een **centrale, org-level pool van 4 self-hosted GitHub Actions runners** voor
de `m0nklabs`-organisatie op host `ai-kvm2`. Deze repo is de deployable
configuratie + versiebeheer voor die pool. Zie `README.md` voor de volledige
architectuur.

## Harde regels (nooit overtreden)

1. **Altijd org-level runners.** Voeg NOOIT een aparte runner per project toe.
   Alle projecten bedienen dezelfde 4 runners.
2. **Alle runners zijn GPU-capabel; GPU-keuze hoort bij het project.** Alle 4
   runners hebben het `gpu`-label en de GPU-omgeving (één machine, zelfde
   GPU's/tools). Voeg NOOIT een aparte GPU-runner toe voor een specifiek project.
   Of een job de GPU inzet, bepaalt het project via zijn per-project env/workflow
   (bijv. `CUDA_VISIBLE_DEVICES`), niet via aparte runners.
3. **GPU-jobs lopen SERIEEL (1 tegelijk).** Er is maar 1 centrale GPU-lock
   (`.gpu.lock` via `bin/gpu-run.sh`). Elke GPU-job moet zijn zware commando's
   wrappen met `bin/gpu-run.sh`, zodat een volgende GPU-job wacht tot de vorige
   klaar is. Nooit GPU-werk zonder de lock-wrapper doen — anders concurreren
   2 jobs op dezelfde kaarten.
4. **Deze repo zelf bevat GEEN secrets.** Nooit runner-registratietokens,
   `m0nk111-admin.token`, PAT's of andere geheimen in deze repo committen.
   Tokens staan lokaal in `~/.secrets/` en worden opgehaald op gebruikstijd.
5. **Geen destructieve acties zonder verificatie.** Stoppen/de-registreren/
   verwijderen van runners, services of scratch-mappen mag pas NADAT is
   bevestigd dat de vervangende pool online en werkend is. Zie "Migratie" onder.
6. **Generieke workflows taal-specifiek, geen wildgroei per project.** CI-kern
   en SAST horen in de centrale reusable workflows (`.github/workflows/*.yml`:
   `python-ci`, `frontend-ci`, `go-ci`, `rust-ci`, `c-cpp-ci`, `csharp-ci`,
   `java-ci`, `ruby-ci`, `swift-ci`, `gpu-ci`, `codeql-ci`, `semgrep-ci`). Een
   project linkt **alleen de taal-workflows voor de talen die het werkelijk
   bevat** via
   `uses: m0nklabs/github-action-runners/.github/workflows/<naam>.yml@main`.
   `python-ci` is **strict**: een falende pytest-suite maakt de check rood. Zet
   `allow-test-failures: true` alleen voor projecten met bekende/deferred
   test-failures — en verwijder het zodra die gefixt zijn, niet als permanente
   ontsnapping. Draai nooit een Go-check in een puur Rust-project (of
   omgekeerd), en zet voor
   CodeQL alleen de talen in de `languages`-input die het project heeft. Voeg
   een nieuwe taal alleen toe als er écht een project-vraag is, niet speculatief.
   **CodeQL-callers** (`codeql-ci`/`codeql-detect`) moeten zelf
   `permissions: security-events: write` declareren in de caller-workflow;
   zonder die write-permission start de reusable niet (`startup_failure`, 0 jobs).
   Op privé-repos skip `codeql-detect` automatisch (code-scanning vereist daar
   betaald Advanced Security); op publieke repos is het gratis. Voor **gratis
   SAST op élke repo (publiek én privé)** gebruik je `semgrep-ci` — Semgrep Core
   is open-source (LGPL) en heeft geen GitHub-licentie nodig. Zet liever
   `semgrep-ci` in op privé-repos dan CodeQL (dat daar toch niet draait).
7. **Cross-repo reusable werkt alleen publiek.** Om projecten deze workflows te
   laten aanroepen, moet de centrale repo **publiek** blijven. Zet haar nooit
   terug naar privé zonder te beseffen dat cross-repo reusable workflows dan
   niet meer werken.

## Namen & locaties (vast, consequent houden)

- Runner-installaties: `actions-runner-1` t/m `actions-runner-4`
- GitHub-namen: `m0nklabs-runner-1` t/m `m0nklabs-runner-4`
- Systemd-units: `actions.runner.m0nklabs.m0nklabs-runner-{1..4}.service`
- Per-project env-conventie: `env/<project>.github-action-runner.env`

## Veilige workflows (gebruik deze scripts, niet handmatig gedoe)

- Nieuwe runner registreren: `./provision/install-runner.sh <n>` (standaard gpu-capabel; `--no-gpu` om af te wijken). Haalt zelf een fresh registratietoken op via `gh` — nooit token handmatig hardcoden.
- Services aanmaken/starten: `sudo ./deploy/install-services.sh`
- Alles in één keer: `GH_TOKEN=... ./provision/install-all.sh`
- Verwijderen: `sudo ./deploy/uninstall-all.sh` (destructief — zie regel 4)

## Migratie-opruiming van de oude setup

De verouderde runners zaten in:
- `/home/flip/github-copilot-config/scratch/github-actions-runners/actions-runner-org{,2..6}`
- `/home/flip/oelala/scratch/github-actions-runners/actions-runner` (repo-runner `oelala-gpu`)

`oelala-gpu` (id 21, repo-scoped) en de stale org-runner (id 39) zijn de te
verwijderen exemplaren. **Wachtvolgorde:** nieuwe pool draait (online) →
testjob slaagt → dan pas de-registreren + services stoppen + mappen verwijderen.
Zet de oude mappen niet zomaar weg terwijl er nog een runner op draait.

## Status-bewaking

- Online/offline via `gh api /orgs/m0nklabs/actions/runners`
- Service-status: `sudo systemctl status actions.runner.m0nklabs.m0nklabs-runner-{1..4}.service`
- Logs: `journalctl -u actions.runner.m0nklabs.m0nklabs-runner-<n>.service -f`

## Taal & communicatie

De gebruiker communiceert primair in het Nederlands. Antwoorden en
commit-berichten mogen; houd de repo zelf (README, comments, commit-berichten)
in het Engels of Nederlands — wees consistent per bestand.