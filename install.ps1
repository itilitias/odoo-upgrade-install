<#
.SYNOPSIS
  Installerer Odoo-oppgraderingspanelet på Windows 10/11 med Docker Desktop (WSL2).

.DESCRIPTION
  Kjør i PowerShell (ikke som administrator trengs bare hvis Docker Desktop skal installeres):

    irm https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main/install.ps1 | iex

  Kjør den på nytt for å oppdatere filene; .env og passordene dine beholdes.
  Valg (miljøvariabler): OUP_DIR, OUP_VERSION, OUP_REGISTRY, OUP_BASE_URL, OUP_YES=1, OUP_DRY_RUN=1.
#>
$ErrorActionPreference = 'Stop'

$BaseUrl = if ($env:OUP_BASE_URL) { $env:OUP_BASE_URL } else { 'https://raw.githubusercontent.com/itilitias/odoo-upgrade-install/main' }
$Dir     = if ($env:OUP_DIR) { $env:OUP_DIR } else { Join-Path $env:USERPROFILE 'odoo-upgrade' }
$Yes     = $env:OUP_YES -eq '1'
$DryRun  = $env:OUP_DRY_RUN -eq '1'

function Say($t)  { Write-Host $t }
function Warn($t) { Write-Host "OBS: $t" -ForegroundColor Yellow }
function Die($t)  { Write-Host "FEIL: $t" -ForegroundColor Red; throw $t }
function Confirm-Step($q) {
  if ($Yes) { return $true }
  $a = Read-Host "$q [J/n]"
  return -not ($a -match '^(n|nei)$')
}

# ---------------------------------------------------------------- system

if ($PSVersionTable.PSVersion.Major -lt 5) { Die 'Trenger PowerShell 5.1 eller nyere.' }
if (-not $IsLinux -and -not $IsMacOS) {
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 19041) { Die 'Trenger Windows 10 versjon 2004 (build 19041) eller nyere, eller Windows 11.' }
}
if (-not [Environment]::Is64BitOperatingSystem) { Die 'Trenger 64-bit Windows.' }

# ---------------------------------------------------------------- Docker

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
  Say 'Docker Desktop er ikke installert.'
  Warn 'Docker Desktop er gratis for virksomheter med under 250 ansatte OG under 10 millioner dollar i omsetning. Ellers trengs betalt lisens.'
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget -and (Confirm-Step 'Installere Docker Desktop nå med winget?')) {
    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
    Say ''
    Say 'Docker Desktop er installert. Start det (Start-menyen), vent til det sier at Docker kjører,'
    Say 'start PowerShell på nytt (maskinen må kanskje startes om først) og kjør denne kommandoen en gang til.'
    return
  }
  Die 'Installer Docker Desktop fra https://www.docker.com/products/docker-desktop/ , start det, og kjør denne kommandoen på nytt.'
}

& docker info *> $null
if ($LASTEXITCODE -ne 0) { Die 'Docker svarer ikke. Start Docker Desktop, vent til det kjører, og prøv igjen.' }
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Die '«docker compose» mangler. Oppdater Docker Desktop.' }

$mem = & docker info --format '{{.MemTotal}}' 2>$null
if ($mem -and ([double]$mem / 1GB) -lt 3) {
  Warn ('Docker har bare ca. {0:N1} GB minne. Anbefalt er minst 4 GB. Endre under Docker Desktop > Settings > Resources, eller i .wslconfig.' -f ([double]$mem / 1GB))
}
Warn 'Windows kjører containerne i en virtuell maskin (WSL2): tregere enn Linux. Bruk Linux til daglig drift.'

# ---------------------------------------------------------------- porter

function Port-Busy([int]$p) {
  try { return [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) } catch { return $false }
}
function Free-Port([int]$want, [int]$fallback) {
  if (Port-Busy $want) { Warn "Port $want er i bruk. Bruker $fallback i stedet."; return $fallback }
  return $want
}

# ---------------------------------------------------------------- filer

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Dir
Say "Mappe: $Dir"

function Get-RepoFile($name) {
  $tmp = "$name.new"
  if (Test-Path -LiteralPath $BaseUrl -PathType Container) { Copy-Item (Join-Path $BaseUrl $name) $tmp -Force }
  else { Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$name" -OutFile $tmp }
  Move-Item -Force $tmp $name
}
Get-RepoFile 'docker-compose.yml'
if (-not (Test-Path .env.example)) { Get-RepoFile '.env.example' }

function New-Secret([int]$len) {
  $bytes = New-Object byte[] 48
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($bytes); $rng.Dispose()
  return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, $len)
}

if (Test-Path .env) {
  Say 'Fant .env fra før: passordene beholdes.'
} else {
  $http  = Free-Port 80 8080
  $https = Free-Port 443 8443
  $panel = Free-Port 8100 8101
  $lines = foreach ($l in (Get-Content .env.example)) {
    if     ($l -like 'POSTGRES_PASSWORD=*') { 'POSTGRES_PASSWORD=' + (New-Secret 40) }
    elseif ($l -like 'SECRET_KEY=*')        { 'SECRET_KEY=' + (New-Secret 64) }
    elseif ($l -like 'SETUP_CODE=*')        { 'SETUP_CODE=' + (New-Secret 16) }
    else { $l }
  }
  $extra = @()
  if ($http  -ne 80)   { $extra += "HTTP_PORT=$http" }
  if ($https -ne 443)  { $extra += "HTTPS_PORT=$https" }
  if ($panel -ne 8100) { $extra += "PANEL_PORT=$panel" }
  if ($env:OUP_VERSION)  { $extra += "OUP_VERSION=$($env:OUP_VERSION)" }
  if ($env:OUP_REGISTRY) { $extra += "OUP_REGISTRY=$($env:OUP_REGISTRY)" }
  # UTF-8 uten BOM og med LF: Docker Compose tåler ikke BOM i .env
  [System.IO.File]::WriteAllText((Join-Path $Dir '.env'), ((@($lines) + $extra) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
  Say 'Laget .env med tilfeldige passord.'
}

if ($DryRun) { Say "Prøvekjøring: filene er laget i $Dir, men ingenting er lastet ned eller startet."; return }

# ---------------------------------------------------------------- start

Say 'Laster ned bildene (første gang tar det noen minutter) ...'
& docker compose pull
if ($LASTEXITCODE -ne 0) { Die 'Kunne ikke laste ned bildene.' }
& docker compose up -d
if ($LASTEXITCODE -ne 0) { Die 'Kunne ikke starte tjenestene. Se: docker compose logs' }

function Env-Value($key, $default) {
  $m = Select-String -Path .env -Pattern "^$key=(.*)$" | Select-Object -Last 1
  if ($m) { return $m.Matches[0].Groups[1].Value } else { return $default }
}
$port = Env-Value 'PANEL_PORT' '8100'
Say 'Venter på at panelet starter ...'
$ok = $false
for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
  try { $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 3; $ok = ($r.StatusCode -eq 200) }
  catch { Start-Sleep -Seconds 2 }
}
if (-not $ok) { Die "Panelet svarer ikke etter 2 minutter. Se: cd $Dir ; docker compose logs panel" }

$code = Env-Value 'SETUP_CODE' ''
Say ''
Say 'Ferdig. Åpne panelet og gjør oppsettet:'
Say "    http://localhost:$port"
Say ''
Say "Oppsettskode (trengs første gang): $code"
Say "Koden står også i $Dir\.env. Oppdatere senere: cd $Dir ; docker compose pull ; docker compose up -d"
