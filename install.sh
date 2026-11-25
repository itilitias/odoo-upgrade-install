#!/bin/sh
# Installerer ITILITI Upgrade Panel for Odoo med Docker. Linux og Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sudo sh
#
# På Mac (Docker Desktop) kjøres den uten sudo. / On Mac (Docker Desktop) run it without sudo.
#   OUP_LANG=nb eller en velger språk på meldingene / OUP_LANG=nb or en picks the message language.
# Kjør den på nytt for å oppdatere filene; .env og passordene dine beholdes.
#
# Valg (miljøvariabler): OUP_DIR (mappe), OUP_VERSION, OUP_REGISTRY, OUP_BASE_URL (hvor filene hentes fra),
#   OUP_YES=1 (ikke spør), OUP_DRY_RUN=1 (lag filene, men ikke last ned bilder eller start).

set -eu

BASE_URL="${OUP_BASE_URL:-https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main}"
OS="$(uname -s)"
ARCH="$(uname -m)"

# Språk: norsk hvis systemet er satt til norsk (eller OUP_LANG=nb), ellers engelsk. Language: Norwegian or English.
case "${OUP_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in nb*|nn*|no*) L=nb ;; *) L=en ;; esac
T() { if [ "$L" = nb ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

say()  { printf '%s\n' "$*"; }
warn() { printf '%s %s\n' "$(T OBS NOTE):" "$*" >&2; }
die()  { printf '%s %s\n' "$(T FEIL ERROR):" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- system

case "$OS" in
  Linux)  DEFAULT_DIR="/opt/odoo-upgrade" ;;
  Darwin) DEFAULT_DIR="$HOME/odoo-upgrade" ;;
  *) die "$(T "Dette skriptet er for Linux og Mac. På Windows brukes install.ps1." "This script is for Linux and Mac. On Windows, use install.ps1.")" ;;
esac
case "$ARCH" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "$(T "Maskintypen $ARCH støttes ikke (trenger 64-bit x86 eller ARM)." "The machine type $ARCH is not supported (needs 64-bit x86 or ARM).")" ;;
esac

if [ "$OS" = "Linux" ] && [ "$(id -u)" -ne 0 ]; then
  die "$(T "Kjør som administrator: curl -fsSL $BASE_URL/install.sh | sudo sh" "Run as administrator: curl -fsSL $BASE_URL/install.sh | sudo sh")"
fi

DIR="${OUP_DIR:-$DEFAULT_DIR}"

confirm() {  # confirm "spørsmål": ja hvis OUP_YES=1 eller svaret er j/y; uten terminal regnes det som ja
  [ "${OUP_YES:-0}" = "1" ] && return 0
  if [ -r /dev/tty ]; then
    printf '%s [%s/n] ' "$1" "$(T J Y)" > /dev/tty
    read -r ans < /dev/tty || ans=""
    case "$ans" in n|N|no|No|nei|Nei) return 1 ;; esac
  fi
  return 0
}

# ---------------------------------------------------------------- Docker

if ! have docker; then
  if [ "$OS" = "Darwin" ]; then
    die "$(T "Docker mangler. Installer Docker Desktop fra https://www.docker.com/products/docker-desktop/ , start det, og kjør dette skriptet på nytt." "Docker is missing. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ , start it, and run this script again.")"
  fi
  say "$(T "Docker er ikke installert." "Docker is not installed.")"
  confirm "$(T "Installere Docker Engine nå (offisielt skript fra get.docker.com)?" "Install Docker Engine now (official script from get.docker.com)?")" || die "$(T "Docker trengs. Installer det og kjør skriptet på nytt." "Docker is required. Install it and run the script again.")"
  have curl || die "$(T "curl mangler. Installer curl og prøv igjen." "curl is missing. Install curl and try again.")"
  curl -fsSL https://get.docker.com | sh
  have systemctl && systemctl enable --now docker >/dev/null 2>&1 || true
fi

docker info >/dev/null 2>&1 || die "$(T "Docker svarer ikke. På Mac: start Docker Desktop. På Linux: sudo systemctl start docker." "Docker is not responding. On Mac: start Docker Desktop. On Linux: sudo systemctl start docker.")"
docker compose version >/dev/null 2>&1 || die "$(T "«docker compose» mangler. Installer docker-compose-plugin (https://docs.docker.com/compose/install/) og prøv igjen." "\"docker compose\" is missing. Install docker-compose-plugin (https://docs.docker.com/compose/install/) and try again.")"

MEM_KB="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
MEM_GB=$(( MEM_KB / 1073741824 ))
[ "$MEM_GB" -ge 3 ] || warn "$(T "Docker har bare ca. ${MEM_GB} GB minne. Panelet anbefaler minst 4 GB, og mer for flere instanser." "Docker has only about ${MEM_GB} GB of memory. The panel recommends at least 4 GB, and more for several instances.")"
if [ "$OS" = "Darwin" ]; then
  warn "$(T "Docker Desktop kjører containerne i en virtuell maskin: tregere enn Linux. Bruk Linux til daglig drift." "Docker Desktop runs the containers in a virtual machine: slower than Linux. Use Linux for daily operation.")"
fi

# ---------------------------------------------------------------- porter

port_busy() {
  if have ss; then ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
  elif have lsof; then lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  elif have nc; then nc -z 127.0.0.1 "$1" >/dev/null 2>&1
  else return 1; fi
}

free_port() {  # free_port <ønsket> <reserve>
  if port_busy "$1"; then
    warn "$(T "Port $1 er i bruk. Bruker $2 i stedet." "Port $1 is in use. Using $2 instead.")" >&2
    echo "$2"
  else
    echo "$1"
  fi
}

# ---------------------------------------------------------------- filer

mkdir -p "$DIR"
cd "$DIR"
say "$(T "Mappe: $DIR" "Folder: $DIR")"

fetch() {  # fetch <navn>
  case "$BASE_URL" in
    file://*|/*) cp "${BASE_URL#file://}/$1" "$1.new" ;;
    *) have curl || die "$(T "curl mangler." "curl is missing.")"
       curl -fsSL "$BASE_URL/$1" -o "$1.new" ;;
  esac
  mv "$1.new" "$1"
}

fetch docker-compose.yml
[ -f .env.example ] || fetch .env.example

rand() { head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-"$1"; }

if [ -f .env ]; then
  say "$(T "Fant .env fra før: passordene beholdes." "Found an existing .env: the passwords are kept.")"
else
  cp .env.example .env
  HTTP_PORT="$(free_port 80 8080)"
  HTTPS_PORT="$(free_port 443 8443)"
  PANEL_PORT="$(free_port 8100 8101)"
  {
    sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(rand 40)|" \
        -e "s|^SECRET_KEY=.*|SECRET_KEY=$(rand 64)|" \
        -e "s|^SETUP_CODE=.*|SETUP_CODE=$(rand 16)|" .env.example
    [ "$HTTP_PORT" = 80 ] || echo "HTTP_PORT=$HTTP_PORT"
    [ "$HTTPS_PORT" = 443 ] || echo "HTTPS_PORT=$HTTPS_PORT"
    [ "$PANEL_PORT" = 8100 ] || echo "PANEL_PORT=$PANEL_PORT"
    [ -z "${OUP_VERSION:-}" ] || echo "OUP_VERSION=$OUP_VERSION"
    [ -z "${OUP_REGISTRY:-}" ] || echo "OUP_REGISTRY=$OUP_REGISTRY"
  } > .env
  chmod 600 .env
  say "$(T "Laget .env med tilfeldige passord." "Created .env with random passwords.")"
fi

if [ "${OUP_DRY_RUN:-0}" = "1" ]; then
  say "$(T "Prøvekjøring: filene er laget i $DIR, men ingenting er lastet ned eller startet." "Dry run: the files are created in $DIR, but nothing has been downloaded or started.")"
  exit 0
fi

# ---------------------------------------------------------------- bilderegister

REG="${OUP_REGISTRY:-$(sed -n 's/^OUP_REGISTRY=//p' .env | tail -1)}"; REG="${REG:-license.labcore.no}"
REG_HOST="${REG%%/*}"
case "$REG_HOST" in
  license.labcore.no|license.*)  # vårt eget register: krever lisensnøkkel (gratisnøkkel finnes)
    if ! grep -qs "\"$REG_HOST\"" "$HOME/.docker/config.json"; then
      KEY="${OUP_LICENSE_KEY:-}"
      if [ -z "$KEY" ] && [ "${OUP_YES:-0}" != "1" ] && [ -r /dev/tty ]; then
        say "$(T "Bildene hentes fra et privat register og krever en nøkkel. Har du ikke en, få en gratis her: https://$REG_HOST/gratis" "The images come from a private registry and need a key. If you do not have one, get a free key here: https://$REG_HOST/gratis")"
        printf '%s ' "$(T "Lisensnøkkel (OUP-...):" "License key (OUP-...):")" > /dev/tty
        read -r KEY < /dev/tty || KEY=""
      fi
      [ -n "$KEY" ] || die "$(T "Lisensnøkkel mangler. Sett OUP_LICENSE_KEY=OUP-... og kjør på nytt. Gratisnøkkel: https://$REG_HOST/gratis" "License key is missing. Set OUP_LICENSE_KEY=OUP-... and run again. Free key: https://$REG_HOST/gratis")"
      printf '%s' "$KEY" | docker login "$REG_HOST" -u lisens --password-stdin >/dev/null 2>&1 \
        || die "$(T "Innloggingen i registeret feilet. Sjekk nøkkelen (og at lisensen ikke er utløpt)." "Login to the registry failed. Check the key (and that the license has not expired).")"
      say "$(T "Innlogget i registeret." "Logged in to the registry.")"
    fi ;;
esac

# ---------------------------------------------------------------- start

say "$(T "Laster ned bildene (første gang tar det noen minutter) ..." "Downloading the images (the first time takes a few minutes) ...")"
docker compose pull
docker compose up -d

PANEL_PORT="$(sed -n 's/^PANEL_PORT=//p' .env | tail -1)"; PANEL_PORT="${PANEL_PORT:-8100}"
say "$(T "Venter på at panelet starter ..." "Waiting for the panel to start ...")"
i=0
until curl -fsS "http://127.0.0.1:$PANEL_PORT/healthz" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -le 60 ] || die "$(T "Panelet svarer ikke etter 2 minutter. Se: cd $DIR && docker compose logs panel" "The panel does not respond after 2 minutes. See: cd $DIR && docker compose logs panel")"
  sleep 2
done

HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$HOST" ] || HOST="localhost"
CODE="$(sed -n 's/^SETUP_CODE=//p' .env | tail -1)"
say ""
say "$(T "Ferdig. Åpne panelet og gjør oppsettet:" "Done. Open the panel and complete the setup:")"
say "    http://$HOST:$PANEL_PORT"
say ""
say "$(T "Oppsettskode (trengs første gang): $CODE" "Setup code (needed the first time): $CODE")"
say "$(T "Koden står også i $DIR/.env. Oppdatere senere: cd $DIR && docker compose pull && docker compose up -d" "The code is also in $DIR/.env. To update later: cd $DIR && docker compose pull && docker compose up -d")"
