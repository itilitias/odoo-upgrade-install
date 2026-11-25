#!/bin/sh
# Installerer Odoo-oppgraderingspanelet med Docker. Linux og Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.sh | sudo sh
#
# På Mac (Docker Desktop) kjøres den uten sudo.
# Kjør den på nytt for å oppdatere filene; .env og passordene dine beholdes.
#
# Valg (miljøvariabler): OUP_DIR (mappe), OUP_VERSION, OUP_REGISTRY, OUP_BASE_URL (hvor filene hentes fra),
#   OUP_YES=1 (ikke spør), OUP_DRY_RUN=1 (lag filene, men ikke last ned bilder eller start).

set -eu

BASE_URL="${OUP_BASE_URL:-https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main}"
OS="$(uname -s)"
ARCH="$(uname -m)"

say()  { printf '%s\n' "$*"; }
warn() { printf 'OBS: %s\n' "$*" >&2; }
die()  { printf 'FEIL: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- system

case "$OS" in
  Linux)  DEFAULT_DIR="/opt/odoo-upgrade" ;;
  Darwin) DEFAULT_DIR="$HOME/odoo-upgrade" ;;
  *) die "Dette skriptet er for Linux og Mac. På Windows brukes install.ps1." ;;
esac
case "$ARCH" in
  x86_64|amd64|aarch64|arm64) ;;
  *) die "Maskintypen $ARCH støttes ikke (trenger 64-bit x86 eller ARM)." ;;
esac

if [ "$OS" = "Linux" ] && [ "$(id -u)" -ne 0 ]; then
  die "Kjør som administrator: curl -fsSL $BASE_URL/install.sh | sudo sh"
fi

DIR="${OUP_DIR:-$DEFAULT_DIR}"

confirm() {  # confirm "spørsmål": ja hvis OUP_YES=1 eller svaret er j/y; uten terminal regnes det som ja
  [ "${OUP_YES:-0}" = "1" ] && return 0
  if [ -r /dev/tty ]; then
    printf '%s [J/n] ' "$1" > /dev/tty
    read -r ans < /dev/tty || ans=""
    case "$ans" in n|N|nei|Nei) return 1 ;; esac
  fi
  return 0
}

# ---------------------------------------------------------------- Docker

if ! have docker; then
  if [ "$OS" = "Darwin" ]; then
    die "Docker mangler. Installer Docker Desktop fra https://www.docker.com/products/docker-desktop/ , start det, og kjør dette skriptet på nytt."
  fi
  say "Docker er ikke installert."
  confirm "Installere Docker Engine nå (offisielt skript fra get.docker.com)?" || die "Docker trengs. Installer det og kjør skriptet på nytt."
  have curl || die "curl mangler. Installer curl og prøv igjen."
  curl -fsSL https://get.docker.com | sh
  have systemctl && systemctl enable --now docker >/dev/null 2>&1 || true
fi

docker info >/dev/null 2>&1 || die "Docker svarer ikke. På Mac: start Docker Desktop. På Linux: sudo systemctl start docker."
docker compose version >/dev/null 2>&1 || die "«docker compose» mangler. Installer docker-compose-plugin (https://docs.docker.com/compose/install/) og prøv igjen."

MEM_KB="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
MEM_GB=$(( MEM_KB / 1073741824 ))
[ "$MEM_GB" -ge 3 ] || warn "Docker har bare ca. ${MEM_GB} GB minne. Panelet anbefaler minst 4 GB, og mer for flere instanser."
if [ "$OS" = "Darwin" ]; then
  warn "Docker Desktop kjører containerne i en virtuell maskin: tregere enn Linux. Bruk Linux til daglig drift."
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
    warn "Port $1 er i bruk. Bruker $2 i stedet." >&2
    echo "$2"
  else
    echo "$1"
  fi
}

# ---------------------------------------------------------------- filer

mkdir -p "$DIR"
cd "$DIR"
say "Mappe: $DIR"

fetch() {  # fetch <navn>
  case "$BASE_URL" in
    file://*|/*) cp "${BASE_URL#file://}/$1" "$1.new" ;;
    *) have curl || die "curl mangler."
       curl -fsSL "$BASE_URL/$1" -o "$1.new" ;;
  esac
  mv "$1.new" "$1"
}

fetch docker-compose.yml
[ -f .env.example ] || fetch .env.example

rand() { head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-"$1"; }

if [ -f .env ]; then
  say "Fant .env fra før: passordene beholdes."
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
  say "Laget .env med tilfeldige passord."
fi

if [ "${OUP_DRY_RUN:-0}" = "1" ]; then
  say "Prøvekjøring: filene er laget i $DIR, men ingenting er lastet ned eller startet."
  exit 0
fi

# ---------------------------------------------------------------- start

say "Laster ned bildene (første gang tar det noen minutter) ..."
docker compose pull
docker compose up -d

PANEL_PORT="$(sed -n 's/^PANEL_PORT=//p' .env | tail -1)"; PANEL_PORT="${PANEL_PORT:-8100}"
say "Venter på at panelet starter ..."
i=0
until curl -fsS "http://127.0.0.1:$PANEL_PORT/healthz" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -le 60 ] || die "Panelet svarer ikke etter 2 minutter. Se: cd $DIR && docker compose logs panel"
  sleep 2
done

HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$HOST" ] || HOST="localhost"
CODE="$(sed -n 's/^SETUP_CODE=//p' .env | tail -1)"
say ""
say "Ferdig. Åpne panelet og gjør oppsettet:"
say "    http://$HOST:$PANEL_PORT"
say ""
say "Oppsettskode (trengs første gang): $CODE"
say "Koden står også i $DIR/.env. Oppdatere senere: cd $DIR && docker compose pull && docker compose up -d"
