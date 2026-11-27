#!/bin/sh
# Fjerner ITILITI Upgrade Panel for Odoo. Linux og Mac. / Removes the panel. Linux and Mac.
#
#   Standard: stopper og fjerner containere og bilder, men BEHOLDER alle data (databaser, backuper, sertifikater).
#   --purge:  sletter også alle data og mappen med .env. Kan ikke angres. Ta backup først.
#
#   sudo sh uninstall.sh
#   sudo sh uninstall.sh --purge
#   curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/uninstall.sh | sudo sh -s -- --purge
#
# Valg (miljøvariabler): OUP_DIR (mappen panelet ligger i), OUP_YES=1 (ikke spør; --purge krever likevel at du skriver SLETT),
#   OUP_CONFIRM=SLETT (bekreftelse for --purge uten terminal), OUP_LANG=nb eller en (språk på meldingene).

set -eu

OS="$(uname -s)"
case "${OUP_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in nb*|nn*|no*) L=nb ;; *) L=en ;; esac
T() { if [ "$L" = nb ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say()  { printf '%s\n' "$*"; }
die()  { printf '%s %s\n' "$(T FEIL ERROR):" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

PURGE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) die "$(T "Ukjent valg: $a (bruk --purge eller ingenting)." "Unknown option: $a (use --purge or nothing).")" ;;
  esac
done

case "$OS" in
  Linux)  DEFAULT_DIR="/opt/odoo-upgrade" ;;
  Darwin) DEFAULT_DIR="$HOME/odoo-upgrade" ;;
  *) die "$(T "Dette skriptet er for Linux og Mac. På Windows brukes uninstall.ps1." "This script is for Linux and Mac. On Windows, use uninstall.ps1.")" ;;
esac
if [ "$OS" = "Linux" ] && [ "$(id -u)" -ne 0 ]; then
  die "$(T "Kjør som administrator: sudo sh uninstall.sh" "Run as administrator: sudo sh uninstall.sh")"
fi
DIR="${OUP_DIR:-$DEFAULT_DIR}"
have docker || die "$(T "Docker finnes ikke på denne maskinen, så det er ingenting å fjerne her." "Docker is not installed on this machine, so there is nothing to remove here.")"
docker info >/dev/null 2>&1 || die "$(T "Docker svarer ikke. Start Docker og prøv igjen." "Docker is not responding. Start Docker and try again.")"

has_tty() { ( : < /dev/tty ) 2>/dev/null; }

ask() {  # ask "spørsmål": ja hvis OUP_YES=1 eller svaret er j/y. Uten terminal og uten OUP_YES regnes det som nei.
  [ "${OUP_YES:-0}" = "1" ] && return 0
  has_tty || return 1
  printf '%s [%s/n] ' "$1" "$(T J Y)" > /dev/tty
  read -r ans < /dev/tty || ans=""
  case "$ans" in j|J|y|Y|ja|Ja|yes|Yes) return 0 ;; *) return 1 ;; esac
}

ask_yes() {  # som ask, men Enter betyr ja: ask_yes "spørsmål". Uten terminal og uten OUP_YES regnes det som nei.
  [ "${OUP_YES:-0}" = "1" ] && return 0
  has_tty || return 1
  printf '%s [%s/n] ' "$1" "$(T J Y)" > /dev/tty
  read -r ans < /dev/tty || ans=""
  case "$ans" in n|N|nei|Nei|no|No) return 1 ;; *) return 0 ;; esac
}

release_license() {  # bruker panelets egen funksjon, så det virker uansett hvor nøkkelen er lagret
  PANEL_ID="$(docker ps --filter 'label=com.docker.compose.project=odoo-upgrade' --filter 'label=com.docker.compose.service=panel' -q 2>/dev/null | head -1)"
  if [ -z "$PANEL_ID" ]; then
    say "  $(T "Panelet kjører ikke, så nøkkelen ble ikke frigjort. Bruk «Bruk nøkkelen her» i det nye panelet." "The panel is not running, so the key was not released. Use \"Use the key here\" in the new panel.")"
    return 0
  fi
  OUT="$(docker exec "$PANEL_ID" python -c "from app import license as l; print(l.release() or 'OK')" 2>&1 | tail -1)" || OUT=""
  case "$OUT" in
    OK) say "  $(T "Lisensnøkkelen er frigjort." "The license key has been released.")" ;;
    "Ingen nøkkel"*) say "  $(T "Det var ikke lagt inn noen lisensnøkkel." "No license key had been entered.")" ;;
    *) say "  $(T "Kunne ikke frigjøre nøkkelen ($OUT). Bruk «Bruk nøkkelen her» i det nye panelet." "Could not release the key ($OUT). Use \"Use the key here\" in the new panel.")" ;;
  esac
}

COMPOSE=""
if [ -f "$DIR/docker-compose.yml" ]; then COMPOSE="docker compose --project-directory $DIR -p odoo-upgrade"; fi

# ---------------------------------------------------------------- hva finnes

# Bare det som tilhører panelet: compose-prosjektet «odoo-upgrade» og alt panelet har merket med oup.instance
PROJ_CONTS="$(docker ps -a --filter label=com.docker.compose.project=odoo-upgrade --format '{{.Names}}')"
INST_CONTS="$(docker ps -a --filter label=oup.instance --format '{{.Names}}')"
IMAGES="$(docker images --filter 'reference=oup-odoo' --format '{{.Repository}}:{{.Tag}}')"
INST_VOLS="$(docker volume ls --filter label=oup.instance --format '{{.Name}}')"
PROJ_VOLS="$(docker volume ls --filter label=com.docker.compose.project=odoo-upgrade --format '{{.Name}}')"

count() { [ -n "$1" ] && printf '%s\n' "$1" | wc -l | tr -d ' ' || echo 0; }
N_PC="$(count "$PROJ_CONTS")"; N_IC="$(count "$INST_CONTS")"; N_IM="$(count "$IMAGES")"
N_IV="$(count "$INST_VOLS")"; N_PV="$(count "$PROJ_VOLS")"

if [ "$N_PC" = 0 ] && [ "$N_IC" = 0 ] && [ "$N_IV" = 0 ] && [ "$N_PV" = 0 ] && [ ! -d "$DIR" ]; then
  say "$(T "Fant ikke noe panel her ($DIR). Ingenting å gjøre." "Found no panel here ($DIR). Nothing to do.")"
  exit 0
fi

say "$(T "Dette fjernes:" "This will be removed:")"
say "  - $(T "$N_PC containere fra panelpakken (panel, database, Caddy, workere, tunnel)" "$N_PC containers from the panel package (panel, database, Caddy, workers, tunnel)")"
say "  - $(T "$N_IC instans-containere som panelet har laget" "$N_IC instance containers created by the panel")"
say "  - $(T "$N_IM Odoo-bilder som panelet har bygget, og bildene til panelpakken" "$N_IM Odoo images built by the panel, and the panel package images")"
if [ "$PURGE" = 1 ]; then
  SIZES="$(docker system df -v 2>/dev/null | awk '/^Local Volumes space usage/{f=1;next} f&&/^$/{f=0} f&&/odoo-upgrade_|oup-/{print $NF " " $1}' | head -20)"
  say "  - $(T "ALLE DATA: $((N_PV + N_IV)) volumer (databaser, backuper, filer, sertifikater)" "ALL DATA: $((N_PV + N_IV)) volumes (databases, backups, files, certificates)")"
  [ -z "$SIZES" ] || printf '%s\n' "$SIZES" | sed 's/^/      /'
  say "  - $(T "Mappen $DIR (inkludert .env)" "The folder $DIR (including .env)")"
  say ""
  say "$(T "Dette kan ikke angres. Har du tatt backup av det du vil beholde?" "This cannot be undone. Have you backed up what you want to keep?")"
  if has_tty; then
    printf '%s ' "$(T "Skriv SLETT for å bekrefte:" "Type SLETT to confirm:")" > /dev/tty
    read -r CONFIRM < /dev/tty || CONFIRM=""
  else
    CONFIRM="${OUP_CONFIRM:-}"
  fi
  [ "$CONFIRM" = "SLETT" ] || die "$(T "Ikke bekreftet. Ingenting er slettet." "Not confirmed. Nothing was deleted.")"
else
  say "  - $(T "Dataene beholdes ($((N_PV + N_IV)) volumer). Kjør med --purge for å slette dem også." "The data is kept ($((N_PV + N_IV)) volumes). Run with --purge to delete it too.")"
  ask_yes "$(T "Fortsette?" "Continue?")" || die "$(T "Avbrutt. Ingenting er endret." "Cancelled. Nothing was changed.")"
fi

# ---------------------------------------------------------------- lisensnøkkelen
if [ -n "$PROJ_CONTS" ]; then
  say ""
  if ask_yes "$(T "Frigjøre lisensnøkkelen først? Da kan du aktivere den på en annen maskin (anbefalt)." "Release the license key first? Then you can activate it on another machine (recommended).")"; then
    release_license
  else
    say "  $(T "Hoppet over. Er nøkkelen ikke frigjort, bruk «Bruk nøkkelen her» i det nye panelet." "Skipped. If the key is not released, use \"Use the key here\" in the new panel.")"
  fi
fi

# ---------------------------------------------------------------- fjern

if [ -n "$INST_CONTS" ]; then
  say "$(T "Fjerner instanser ..." "Removing instances ...")"
  # shellcheck disable=SC2086
  docker rm -f $INST_CONTS >/dev/null 2>&1 || true
fi
if [ -n "$COMPOSE" ]; then
  say "$(T "Stopper og fjerner panelpakken ..." "Stopping and removing the panel package ...")"
  if [ "$PURGE" = 1 ]; then
    COMPOSE_PROFILES="*" $COMPOSE down --remove-orphans --rmi all --volumes 2>&1 | sed 's/^/  /' || true
  else
    COMPOSE_PROFILES="*" $COMPOSE down --remove-orphans --rmi all 2>&1 | sed 's/^/  /' || true
  fi
elif [ -n "$PROJ_CONTS" ]; then
  # shellcheck disable=SC2086
  docker rm -f $PROJ_CONTS >/dev/null 2>&1 || true
fi
docker rm -f oup-updater >/dev/null 2>&1 || true
if [ -n "$IMAGES" ]; then
  # shellcheck disable=SC2086
  docker rmi -f $IMAGES >/dev/null 2>&1 || docker rmi -f $IMAGES 2>&1 | sed 's/^/  /' || true
fi
if [ "$PURGE" = 1 ]; then
  say "$(T "Sletter data ..." "Deleting data ...")"
  # shellcheck disable=SC2086
  [ -z "$INST_VOLS" ] || docker volume rm -f $INST_VOLS >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  [ -z "$PROJ_VOLS" ] || docker volume rm -f $PROJ_VOLS >/dev/null 2>&1 || true
  # Mappen slettes bare hvis den ser ut som panelets mappe
  if [ -f "$DIR/docker-compose.yml" ] && [ -f "$DIR/.env.example" ]; then
    cd / && rm -rf "$DIR"
  fi
fi

say ""
say "$(T "Ferdig." "Done.")"
if [ "$PURGE" != 1 ]; then
  say "$(T "Dataene er beholdt. Installerer du på nytt i $DIR, tas de i bruk igjen." "The data is kept. If you reinstall in $DIR, it is picked up again.")"
fi
say "$(T "Dette gjør du selv, om du brukte det:" "Do these yourself, if you used them:")"
say "  - $(T "Fjern tunnelen og vertsnavnet i Cloudflare Zero Trust (Networks → Tunnels)." "Remove the tunnel and hostname in Cloudflare Zero Trust (Networks → Tunnels).")"
say "  - $(T "Fjern DNS-postene for domenet ditt." "Remove the DNS records for your domain.")"
say "  - $(T "Si opp lisensen hvis den er betalt." "Cancel the license if it is paid.")"
say "  - $(T "Docker selv er ikke fjernet." "Docker itself is not removed.")"
