# Odoo-oppgraderingspanel: installasjon

Panelet tester og kjører Odoo-oppgraderinger med OCA OpenUpgrade, uten kommandolinje. Dette repoet har bare det du trenger for å installere det. Selve programmet hentes som ferdige Docker-bilder.

## Installer

**Linux** (anbefalt til daglig drift). Installerer Docker hvis det mangler:

```bash
curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sudo sh
```

**Windows 10/11** (Docker Desktop med WSL2), i PowerShell:

```powershell
irm https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.ps1 | iex
```

**Mac** (Docker Desktop må være installert og startet):

```bash
curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sh
```

Skriptet lager en mappe (`/opt/odoo-upgrade` på Linux, `odoo-upgrade` i hjemmemappen ellers), genererer tilfeldige passord i `.env`, laster ned bildene og starter alt. Til slutt skriver det ut adressen til panelet og en **oppsettskode**. Åpne adressen, skriv inn koden, og følg oppsettveiviseren.

Kjør samme kommando på nytt for å oppdatere installasjonsfilene. `.env` og passordene beholdes.

## Krav

* 4 GB minne eller mer (mer jo flere instanser du kjører), 20 GB disk eller mer.
* 64-bit x86 eller ARM.
* Port 80 og 443 åpne hvis du bruker eget domene (for HTTPS). Er de opptatt, velger skriptet andre porter og sier fra.
* **Windows og Mac** kjører containerne i en virtuell maskin, som er tregere og bruker mer minne. Bruk Linux til drift.
* **Docker Desktop** er gratis for virksomheter med under 250 ansatte og under 10 millioner dollar i omsetning. Docker Engine på Linux har ikke det kravet.

## Drift

```bash
cd /opt/odoo-upgrade
docker compose ps                         # status
docker compose logs -f panel              # logg
docker compose pull && docker compose up -d   # oppdater
```

Dataene ligger i Docker-volumene `pgdata` og `oup-data`. Ta backup av begge. Sett `OUP_DATA` i `.env` til en mappe (for eksempel `/srv/oup`) hvis du vil ha filene i en vanlig mappe.

## Andre filer

* `docker-compose.yml`: hele oppsettet (panel, PostgreSQL, OpenUpgrade-workere og Caddy som ordner HTTPS).
* `.env.example`: alle valg. Installasjonen lager `.env` av den.

Agenten som installeres i kundens Odoo ligger i [odoo-upgrade-agent](https://github.com/itilitias/odoo-upgrade-agent).
