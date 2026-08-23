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
2. **GPU is optioneel per runner, niet per project.** Voeg geen nieuwe GPU-runner
   toe voor een specifiek project. Gebruik de bestaande `gpu`-gelabelde runners
   (runner-1, runner-2) en project-specifieke env in het project zelf.
3. **Deze repo zelf bevat GEEN secrets.** Nooit runner-registratietokens,
   `m0nk111-admin.token`, PAT's of andere geheimen in deze repo committen.
   Tokens staan lokaal in `~/.secrets/` en worden opgehaald op gebruikstijd.
4. **Geen destructieve acties zonder verificatie.** Stoppen/de-registreren/
   verwijderen van runners, services of scratch-mappen mag pas NADAT is
   bevestigd dat de vervangende pool online en werkend is. Zie "Migratie" onder.

## Namen & locaties (vast, consequent houden)

- Runner-installaties: `actions-runner-1` t/m `actions-runner-4`
- GitHub-namen: `m0nklabs-runner-1` t/m `m0nklabs-runner-4`
- Systemd-units: `actions.runner.m0nklabs.m0nklabs-runner-{1..4}.service`
- Per-project env-conventie: `env/<project>.github-action-runner.env`

## Veilige workflows (gebruik deze scripts, niet handmatig gedoe)

- Nieuwe runner registreren: `./provision/install-runner.sh <n> [--gpu]`
  (haalt zelf een fresh registratietoken op via `gh` — nooit token handmatig hardcoden)
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
