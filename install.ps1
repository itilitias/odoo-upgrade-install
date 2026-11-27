<#
.SYNOPSIS
  Installerer ITILITI Upgrade Panel for Odoo på Windows 10/11 med Docker Desktop (WSL2).

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

# Språk: norsk hvis Windows er satt til norsk (eller OUP_LANG=nb), ellers engelsk. Language: Norwegian or English.
$Lang = if ($env:OUP_LANG) { $env:OUP_LANG } else { (Get-UICulture).Name }
$Nb = $Lang -match '^(nb|nn|no)'
function T($no, $en) { if ($Nb) { $no } else { $en } }

function Say($t)  { Write-Host $t }
function Warn($t) { Write-Host "$(T 'OBS' 'NOTE'): $t" -ForegroundColor Yellow }
function Die($t)  { Write-Host "$(T 'FEIL' 'ERROR'): $t" -ForegroundColor Red; throw $t }
function Confirm-Step($q) {
  if ($Yes) { return $true }
  $a = Read-Host "$q [$(T 'J' 'Y')/n]"
  return -not ($a -match '^(n|no|nei)$')
}

# ---------------------------------------------------------------- system

if ($PSVersionTable.PSVersion.Major -lt 5) { Die (T 'Trenger PowerShell 5.1 eller nyere.' 'Needs PowerShell 5.1 or newer.') }
if (-not $IsLinux -and -not $IsMacOS) {
  $build = [Environment]::OSVersion.Version.Build
  if ($build -lt 19041) { Die (T 'Trenger Windows 10 versjon 2004 (build 19041) eller nyere, eller Windows 11.' 'Needs Windows 10 version 2004 (build 19041) or newer, or Windows 11.') }
}
if (-not [Environment]::Is64BitOperatingSystem) { Die (T 'Trenger 64-bit Windows.' 'Needs 64-bit Windows.') }

# ---------------------------------------------------------------- Docker

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Docker Desktop kjører containerne i WSL2 (Windows' innebygde virtuelle Linux). Gir true hvis skriptet må stoppe her.
function Ensure-Wsl {
  $has = $false
  if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { & wsl.exe --status *> $null; $has = ($LASTEXITCODE -eq 0) }
  if ($has) { return $false }
  Say ''
  Say (T 'WSL2 er ikke slått på på denne maskinen.' 'WSL2 is not turned on on this machine.')
  Say (T 'Hva er det? Docker Desktop kjører containerne i en liten, innebygd Linux-maskin (WSL2). Windows må ha funksjonene «Windows Subsystem for Linux» og «Virtual Machine Platform» slått på for at det skal virke.' 'What is it? Docker Desktop runs the containers in a small built-in Linux machine (WSL2). Windows needs the features "Windows Subsystem for Linux" and "Virtual Machine Platform" turned on for it to work.')
  Say (T 'Hva skjer? Kommandoen «wsl --install --no-distribution» slår på disse funksjonene. Den laster ned litt fra Microsoft, installerer ingen Linux-distribusjon, og rører ikke filene dine. Maskinen må startes på nytt etterpå.' 'What happens? The command "wsl --install --no-distribution" turns these features on. It downloads a little from Microsoft, installs no Linux distribution, and does not touch your files. The machine must be restarted afterwards.')
  if (-not (Confirm-Step (T 'Slå på WSL2 nå?' 'Turn on WSL2 now?'))) {
    Say (T 'Hoppet over. Du kan gjøre det selv senere: åpne PowerShell som administrator, kjør «wsl --install --no-distribution», og start maskinen på nytt.' 'Skipped. You can do it yourself later: open PowerShell as administrator, run "wsl --install --no-distribution", and restart the machine.')
    return $false
  }
  if (-not (Test-Admin)) {
    Say (T 'Dette krever administrator. Åpne PowerShell som administrator (høyreklikk på PowerShell i Start-menyen, «Kjør som administrator») og kjør denne kommandoen på nytt.' 'This needs administrator rights. Open PowerShell as administrator (right-click PowerShell in the Start menu, "Run as administrator") and run this command again.')
    return $true
  }
  # wsl.exe skriver UTF-16; Out-Host holder utskriften utenfor returverdien til funksjonen
  $oldEnc = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    & wsl.exe --install --no-distribution | Out-Host
    if ($LASTEXITCODE -ne 0) { & wsl.exe --install | Out-Host }
  } finally { [Console]::OutputEncoding = $oldEnc }
  Say ''
  Say (T 'WSL2 er slått på. Start maskinen på nytt, start Docker Desktop (Start-menyen), vent til det sier at Docker kjører, og kjør denne kommandoen en gang til.' 'WSL2 is turned on. Restart the machine, start Docker Desktop (Start menu), wait until it says Docker is running, and run this command once more.')
  return $true
}

$dockerOk = $false
if (Get-Command docker -ErrorAction SilentlyContinue) { & docker info *> $null; $dockerOk = ($LASTEXITCODE -eq 0) }
if (-not $dockerOk) { if (Ensure-Wsl) { return } }

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
  Say (T 'Docker Desktop er ikke installert.' 'Docker Desktop is not installed.')
  Warn (T 'Docker Desktop er gratis for virksomheter med under 250 ansatte OG under 10 millioner dollar i omsetning. Ellers trengs betalt lisens.' 'Docker Desktop is free for businesses with fewer than 250 employees AND less than 10 million dollars in revenue. Otherwise a paid license is required.')
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget -and (Confirm-Step (T 'Installere Docker Desktop nå med winget?' 'Install Docker Desktop now with winget?'))) {
    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
    Say ''
    Say (T 'Docker Desktop er installert. Start det (Start-menyen), vent til det sier at Docker kjører,' 'Docker Desktop is installed. Start it (Start menu), wait until it says Docker is running,')
    Say (T 'start PowerShell på nytt (maskinen må kanskje startes om først) og kjør denne kommandoen en gang til.' 'start PowerShell again (the machine may need a restart first) and run this command once more.')
    Say (T 'Du trenger ingen konto hos Docker: hopp over innlogging hvis Docker Desktop ber om det.' 'You do not need a Docker account: skip the sign-in if Docker Desktop asks for it.')
    return
  }
  Die (T 'Installer Docker Desktop fra https://www.docker.com/products/docker-desktop/ , start det, og kjør denne kommandoen på nytt.' 'Install Docker Desktop from https://www.docker.com/products/docker-desktop/ , start it, and run this command again.')
}

& docker info *> $null
if ($LASTEXITCODE -ne 0) { Die (T 'Docker svarer ikke. Start Docker Desktop (Start-menyen), vent til det sier at Docker kjører, og prøv igjen. Du trenger ingen konto hos Docker: hopp over innlogging. Sier Docker Desktop at WSL2 mangler, åpne PowerShell som administrator, kjør «wsl --install --no-distribution», og start maskinen på nytt.' 'Docker is not responding. Start Docker Desktop (Start menu), wait until it says Docker is running, and try again. You do not need a Docker account: skip the sign-in. If Docker Desktop says WSL2 is missing, open PowerShell as administrator, run "wsl --install --no-distribution", and restart the machine.') }
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Die (T '«docker compose» mangler. Oppdater Docker Desktop.' '"docker compose" is missing. Update Docker Desktop.') }

$mem = & docker info --format '{{.MemTotal}}' 2>$null
if ($mem -and ([double]$mem / 1GB) -lt 3) {
  Warn ((T 'Docker har bare ca. {0:N1} GB minne. Anbefalt er minst 4 GB. Endre under Docker Desktop > Settings > Resources, eller i .wslconfig.' 'Docker has only about {0:N1} GB of memory. At least 4 GB is recommended. Change it under Docker Desktop > Settings > Resources, or in .wslconfig.') -f ([double]$mem / 1GB))
}
Warn (T 'Windows kjører containerne i en virtuell maskin (WSL2): tregere enn Linux. Bruk Linux til daglig drift.' 'Windows runs the containers in a virtual machine (WSL2): slower than Linux. Use Linux for daily operation.')

# ---------------------------------------------------------------- porter

function Port-Busy([int]$p) {
  try { return [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) } catch { return $false }
}
function Free-Port([int]$want, [int]$fallback) {
  if (Port-Busy $want) { Warn (T "Port $want er i bruk. Bruker $fallback i stedet." "Port $want is in use. Using $fallback instead."); return $fallback }
  return $want
}

# ---------------------------------------------------------------- filer

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Dir
Say (T "Mappe: $Dir" "Folder: $Dir")

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
  Say (T 'Fant .env fra før: passordene beholdes.' 'Found an existing .env: the passwords are kept.')
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
  $tunnel = $env:OUP_TUNNEL_TOKEN
  if (-not $tunnel -and -not $Yes) {
    Say (T 'Valgfritt: Cloudflare Tunnel (anbefalt) gir adresser og HTTPS uten at du åpner porter. Lag en tunnel i Cloudflare Zero Trust og lim inn tokenet her. Trykk Enter for å hoppe over.' 'Optional: Cloudflare Tunnel (recommended) gives you addresses and HTTPS without opening ports. Create a tunnel in Cloudflare Zero Trust and paste the token here. Press Enter to skip.')
    $tunnel = Read-Host (T 'Tunnel-token' 'Tunnel token')
  }
  $extra = @()
  if ($tunnel) { $extra += 'COMPOSE_PROFILES=tunnel'; $extra += "CLOUDFLARE_TUNNEL_TOKEN=$tunnel"; $extra += 'INSTANCE_DOMAIN_HTTPS=cloudflare' }
  if ($http  -ne 80)   { $extra += "HTTP_PORT=$http" }
  if ($https -ne 443)  { $extra += "HTTPS_PORT=$https" }
  if ($panel -ne 8100) { $extra += "PANEL_PORT=$panel" }
  if ($env:OUP_VERSION)  { $extra += "OUP_VERSION=$($env:OUP_VERSION)" }
  if ($env:OUP_REGISTRY) { $extra += "OUP_REGISTRY=$($env:OUP_REGISTRY)" }
  # UTF-8 uten BOM og med LF: Docker Compose tåler ikke BOM i .env
  [System.IO.File]::WriteAllText((Join-Path $Dir '.env'), ((@($lines) + $extra) -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
  Say (T 'Laget .env med tilfeldige passord.' 'Created .env with random passwords.')
}

if ($DryRun) { Say (T "Prøvekjøring: filene er laget i $Dir, men ingenting er lastet ned eller startet." "Dry run: the files are created in $Dir, but nothing has been downloaded or started."); return }

# ---------------------------------------------------------------- bilderegister

$Reg = if ($env:OUP_REGISTRY) { $env:OUP_REGISTRY } else { 'license.itilitilabs.com' }
$RegHost = ($Reg -split '/')[0]
if ($RegHost -like 'license.*') {
  $cfg = Join-Path $env:USERPROFILE '.docker\config.json'
  $loggedIn = (Test-Path $cfg) -and ((Get-Content $cfg -Raw) -match [regex]::Escape("`"$RegHost`""))
  if (-not $loggedIn) {
    $Key = $env:OUP_LICENSE_KEY
    if (-not $Key -and -not $Yes) {
      Say (T "Bildene hentes fra et privat register og krever en nøkkel. Har du ikke en, få en gratis her: https://$RegHost/gratis" "The images come from a private registry and need a key. If you do not have one, get a free key here: https://$RegHost/gratis")
      $Key = Read-Host (T 'Lisensnøkkel (OUP-...)' 'License key (OUP-...)')
    }
    if (-not $Key) { Die (T "Lisensnøkkel mangler. Sett `$env:OUP_LICENSE_KEY og kjør på nytt. Gratisnøkkel: https://$RegHost/gratis" "License key is missing. Set `$env:OUP_LICENSE_KEY and run again. Free key: https://$RegHost/gratis") }
    $Key | & docker login $RegHost -u lisens --password-stdin *> $null
    if ($LASTEXITCODE -ne 0) { Die (T 'Innloggingen i registeret feilet. Sjekk nøkkelen (og at lisensen ikke er utløpt).' 'Login to the registry failed. Check the key (and that the license has not expired).') }
    Say (T 'Innlogget i registeret.' 'Logged in to the registry.')
  }
}

# ---------------------------------------------------------------- start

Say (T 'Laster ned bildene (første gang tar det noen minutter) ...' 'Downloading the images (the first time takes a few minutes) ...')
& docker compose pull
if ($LASTEXITCODE -ne 0) { Die (T 'Kunne ikke laste ned bildene.' 'Could not download the images.') }
& docker compose up -d
if ($LASTEXITCODE -ne 0) { Die (T 'Kunne ikke starte tjenestene. Se: docker compose logs' 'Could not start the services. See: docker compose logs') }

function Env-Value($key, $default) {
  $m = Select-String -Path .env -Pattern "^$key=(.*)$" | Select-Object -Last 1
  if ($m) { return $m.Matches[0].Groups[1].Value } else { return $default }
}
$port = Env-Value 'PANEL_PORT' '8100'
Say (T 'Venter på at panelet starter ...' 'Waiting for the panel to start ...')
$ok = $false
for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
  try { $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 3; $ok = ($r.StatusCode -eq 200) }
  catch { Start-Sleep -Seconds 2 }
}
if (-not $ok) { Die (T "Panelet svarer ikke etter 2 minutter. Se: cd $Dir ; docker compose logs panel" "The panel does not respond after 2 minutes. See: cd $Dir ; docker compose logs panel") }

$code = Env-Value 'SETUP_CODE' ''
Say ''
Say (T 'Ferdig. Åpne panelet og gjør oppsettet:' 'Done. Open the panel and complete the setup:')
Say "    http://localhost:$port"
Say ''
if (Select-String -Path .env -Pattern '^CLOUDFLARE_TUNNEL_TOKEN=.' -Quiet) {
  Say (T 'Cloudflare Tunnel er slått på. I Cloudflare legger du til et vertsnavn (for eksempel *.firma.no) med tjeneste http://caddy:80.' 'Cloudflare Tunnel is on. In Cloudflare, add a hostname (for example *.company.com) with service http://caddy:80.')
}
Say (T "Oppsettskode (trengs første gang): $code" "Setup code (needed the first time): $code")
Say (T "Koden står også i $Dir\.env. Oppdatere senere: cd $Dir ; docker compose pull ; docker compose up -d" "The code is also in $Dir\.env. To update later: cd $Dir ; docker compose pull ; docker compose up -d")
