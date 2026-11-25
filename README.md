# ITILITI Upgrade Panel for Odoo: installation

**English** | [Norsk](#norsk)

## ITILITI Upgrade Panel for Odoo: installation

The panel tests and runs Odoo upgrades with OCA OpenUpgrade, without a command line. This repository contains only what you need to install it. The application itself is pulled as ready-made Docker images.

### Install

**Linux** (recommended for production). Installs Docker if it is missing:

```bash
curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sudo sh
```

**Windows 10/11** (Docker Desktop with WSL2), in PowerShell:

```powershell
irm https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.ps1 | iex
```

**Mac** (Docker Desktop must be installed and running):

```bash
curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sh
```

The script creates a folder (`/opt/odoo-upgrade` on Linux, `odoo-upgrade` in your home folder otherwise), generates random passwords in `.env`, downloads the images and starts everything. At the end it prints the address of the panel and a **setup code**. Open the address, enter the code and follow the setup wizard.

Run the same command again to update the installation files. `.env` and the passwords are kept.

> The installer messages are currently in Norwegian. The panel itself is being translated.

### Requirements

* 4 GB RAM or more (more with more instances), 20 GB disk or more.
* 64-bit x86 or ARM.
* Ports 80 and 443 open if you use your own domain (for HTTPS). If they are taken, the script picks other ports and tells you.
* **Windows and Mac** run the containers in a virtual machine, which is slower and uses more memory. Use Linux for production.
* **Docker Desktop** is free for companies with fewer than 250 employees and less than USD 10 million in revenue. Docker Engine on Linux has no such requirement.

### Operation

```bash
cd /opt/odoo-upgrade
docker compose ps                             # status
docker compose logs -f panel                  # logs
docker compose pull && docker compose up -d   # update
```

Data lives in the Docker volumes `pgdata` and `oup-data`. Back up both. Set `OUP_DATA` in `.env` to a folder (for example `/srv/oup`) if you want the files in a regular folder.

### Other files

* `docker-compose.yml`: the whole setup (panel, PostgreSQL, OpenUpgrade workers and Caddy for HTTPS).
* `.env.example`: all options. The installer creates `.env` from it.

The agent installed in the customer's Odoo is in [odoo-upgrade-agent](https://github.com/itilitias/odoo-upgrade-agent). Open-source components and their licenses: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

# Norsk

## ITILITI Upgrade Panel for Odoo: installasjon

Panelet tester og kjører Odoo-oppgraderinger med OCA OpenUpgrade, uten kommandolinje. Dette repoet har bare det du trenger for å installere det. Selve programmet hentes som ferdige Docker-bilder.

### Installer

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

### Krav

* 4 GB minne eller mer (mer jo flere instanser du kjører), 20 GB disk eller mer.
* 64-bit x86 eller ARM.
* Port 80 og 443 åpne hvis du bruker eget domene (for HTTPS). Er de opptatt, velger skriptet andre porter og sier fra.
* **Windows og Mac** kjører containerne i en virtuell maskin, som er tregere og bruker mer minne. Bruk Linux til drift.
* **Docker Desktop** er gratis for virksomheter med under 250 ansatte og under 10 millioner dollar i omsetning. Docker Engine på Linux har ikke det kravet.

### Drift

```bash
cd /opt/odoo-upgrade
docker compose ps                         # status
docker compose logs -f panel              # logg
docker compose pull && docker compose up -d   # oppdater
```

Dataene ligger i Docker-volumene `pgdata` og `oup-data`. Ta backup av begge. Sett `OUP_DATA` i `.env` til en mappe (for eksempel `/srv/oup`) hvis du vil ha filene i en vanlig mappe.

### Andre filer

* `docker-compose.yml`: hele oppsettet (panel, PostgreSQL, OpenUpgrade-workere og Caddy som ordner HTTPS).
* `.env.example`: alle valg. Installasjonen lager `.env` av den.

Agenten som installeres i kundens Odoo ligger i [odoo-upgrade-agent](https://github.com/itilitias/odoo-upgrade-agent). Åpen kildekode-komponenter og lisensene deres: se [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
