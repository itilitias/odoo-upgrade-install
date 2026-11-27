<#
.SYNOPSIS
  Fjerner ITILITI Upgrade Panel for Odoo på Windows. / Removes the panel on Windows.

.DESCRIPTION
  Standard: stopper og fjerner containere og bilder, men BEHOLDER alle data (databaser, backuper, sertifikater).
  -Purge:   sletter også alle data og mappen med .env. Kan ikke angres. Ta backup først.

    .\uninstall.ps1
    .\uninstall.ps1 -Purge

  Valg (miljøvariabler): OUP_DIR (mappen panelet ligger i), OUP_YES=1 (ikke spør; -Purge krever likevel at du skriver SLETT),
  OUP_CONFIRM=SLETT (bekreftelse for -Purge uten terminal), OUP_LANG=nb eller en (språk på meldingene).
#>
param([switch]$Purge)
$ErrorActionPreference = 'Stop'

$Dir = if ($env:OUP_DIR) { $env:OUP_DIR } else { Join-Path $env:USERPROFILE 'odoo-upgrade' }
$Yes = $env:OUP_YES -eq '1'
$Lang = if ($env:OUP_LANG) { $env:OUP_LANG } else { (Get-UICulture).Name }
$Nb = $Lang -match '^(nb|nn|no)'
function T($no, $en) { if ($Nb) { $no } else { $en } }
function Say($t) { Write-Host $t }
function Die($t) { Write-Host "$(T 'FEIL' 'ERROR'): $t" -ForegroundColor Red; throw $t }
function Lines($cmdOutput) { @($cmdOutput | Where-Object { $_ -and "$_".Trim() }) }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die (T 'Docker finnes ikke på denne maskinen, så det er ingenting å fjerne her.' 'Docker is not installed on this machine, so there is nothing to remove here.') }
docker info *> $null
if ($LASTEXITCODE -ne 0) { Die (T 'Docker svarer ikke. Start Docker Desktop og prøv igjen.' 'Docker is not responding. Start Docker Desktop and try again.') }

# ---------------------------------------------------------------- hva finnes
# Bare det som tilhører panelet: compose-prosjektet «odoo-upgrade» og alt panelet har merket med oup.instance
$projConts = Lines (docker ps -a --filter 'label=com.docker.compose.project=odoo-upgrade' --format '{{.Names}}')
$instConts = Lines (docker ps -a --filter 'label=oup.instance' --format '{{.Names}}')
$images    = Lines (docker images --filter 'reference=oup-odoo' --format '{{.Repository}}:{{.Tag}}')
$instVols  = Lines (docker volume ls --filter 'label=oup.instance' --format '{{.Name}}')
$projVols  = Lines (docker volume ls --filter 'label=com.docker.compose.project=odoo-upgrade' --format '{{.Name}}')
$haveCompose = Test-Path (Join-Path $Dir 'docker-compose.yml')

if (-not $projConts -and -not $instConts -and -not $instVols -and -not $projVols -and -not (Test-Path $Dir)) {
  Say (T "Fant ikke noe panel her ($Dir). Ingenting å gjøre." "Found no panel here ($Dir). Nothing to do.")
  return
}

Say (T 'Dette fjernes:' 'This will be removed:')
Say ("  - " + (T "$($projConts.Count) containere fra panelpakken (panel, database, Caddy, workere, tunnel)" "$($projConts.Count) containers from the panel package (panel, database, Caddy, workers, tunnel)"))
Say ("  - " + (T "$($instConts.Count) instans-containere som panelet har laget" "$($instConts.Count) instance containers created by the panel"))
Say ("  - " + (T "$($images.Count) Odoo-bilder som panelet har bygget, og bildene til panelpakken" "$($images.Count) Odoo images built by the panel, and the panel package images"))
$nVol = $projVols.Count + $instVols.Count
if ($Purge) {
  Say ("  - " + (T "ALLE DATA: $nVol volumer (databaser, backuper, filer, sertifikater)" "ALL DATA: $nVol volumes (databases, backups, files, certificates)"))
  Say ("  - " + (T "Mappen $Dir (inkludert .env)" "The folder $Dir (including .env)"))
  Say ''
  Say (T 'Dette kan ikke angres. Har du tatt backup av det du vil beholde?' 'This cannot be undone. Have you backed up what you want to keep?')
  $confirm = $env:OUP_CONFIRM
  if (-not $confirm -and [Environment]::UserInteractive) { $confirm = Read-Host (T 'Skriv SLETT for å bekrefte' 'Type SLETT to confirm') }
  if ($confirm -ne 'SLETT') { Die (T 'Ikke bekreftet. Ingenting er slettet.' 'Not confirmed. Nothing was deleted.') }
} else {
  Say ("  - " + (T "Dataene beholdes ($nVol volumer). Kjør med -Purge for å slette dem også." "The data is kept ($nVol volumes). Run with -Purge to delete it too."))
  if (-not $Yes) {
    $a = Read-Host "$(T 'Fortsette?' 'Continue?') [$(T 'J' 'Y')/n]"
    if ($a -notmatch '^(j|y|ja|yes)$') { Die (T 'Avbrutt. Ingenting er endret.' 'Cancelled. Nothing was changed.') }
  }
}

# ---------------------------------------------------------------- fjern
# Docker skriver fremdrift til stderr; det skal ikke stoppe opprydningen
$ErrorActionPreference = 'Continue'
if ($instConts) {
  Say (T 'Fjerner instanser ...' 'Removing instances ...')
  & docker rm -f @instConts *> $null
}
if ($haveCompose) {
  Say (T 'Stopper og fjerner panelpakken ...' 'Stopping and removing the panel package ...')
  $env:COMPOSE_PROFILES = '*'
  $args2 = @('compose', '--project-directory', $Dir, '-p', 'odoo-upgrade', 'down', '--remove-orphans', '--rmi', 'all')
  if ($Purge) { $args2 += '--volumes' }
  & docker @args2 2>&1 | ForEach-Object { "  $_" }
} elseif ($projConts) {
  & docker rm -f @projConts *> $null
}
if ($images) { & docker rmi -f @images *> $null }
if ($Purge) {
  Say (T 'Sletter data ...' 'Deleting data ...')
  if ($instVols) { & docker volume rm -f @instVols *> $null }
  if ($projVols) { & docker volume rm -f @projVols *> $null }
  # Mappen slettes bare hvis den ser ut som panelets mappe
  if ((Test-Path (Join-Path $Dir 'docker-compose.yml')) -and (Test-Path (Join-Path $Dir '.env.example'))) {
    Set-Location $env:USERPROFILE
    Remove-Item -Recurse -Force $Dir
  }
}

# ---------------------------------------------------------------- valgfritt: Docker Desktop og WSL
# Dette kan brukes av andre programmer på maskinen, så det spørres alltid, svaret er nei som standard,
# og det gjøres aldri med OUP_YES=1.
function Get-WslDistros {
  try {
    $oldEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $l = & wsl.exe -l -q 2>$null
    [Console]::OutputEncoding = $oldEnc
    return @($l | ForEach-Object { ("$_" -replace "`0", '').Trim() } | Where-Object { $_ -and $_ -notmatch '^docker-desktop' })
  } catch { return @() }
}
function Ask-No($q) {
  if ($Yes -or -not [Environment]::UserInteractive) { return $false }
  $a = Read-Host "$q [$(T 'j' 'y')/N]"
  return ($a -match '^(j|y|ja|yes)$')
}

$dockerRemoved = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
  Say ''
  Say (T 'Docker Desktop er fortsatt installert. Det fjernes ikke av avinstalleringen over, og brukes kanskje av andre programmer.' 'Docker Desktop is still installed. The uninstall above did not remove it, and other programs may use it.')
  if (Ask-No (T 'Fjerne Docker Desktop også? Da slutter Docker å virke for ALLE programmer på maskinen.' 'Remove Docker Desktop too? Then Docker stops working for ALL programs on this machine.')) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
      & winget uninstall -e --id Docker.DockerDesktop | Out-Host
      $dockerRemoved = $true
    } else {
      Say (T 'Fant ikke winget. Fjern Docker Desktop selv under Innstillinger -> Apper.' 'Could not find winget. Remove Docker Desktop yourself under Settings -> Apps.')
    }
  }
}
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
  $others = Get-WslDistros
  if ($others.Count -gt 0) {
    Say ''
    Say ((T 'WSL har andre Linux-installasjoner som ikke hører til panelet: ' 'WSL has other Linux installations that do not belong to the panel: ') + ($others -join ', '))
    Say (T 'Derfor lar vi WSL stå.' 'So we leave WSL in place.')
  } elseif (Ask-No (T 'Fjerne WSL også? Det slutter å virke for alle programmer som bruker det. Funksjonene i Windows (Virtual Machine Platform) står igjen, og er uskadelige.' 'Remove WSL too? It stops working for all programs that use it. The Windows features (Virtual Machine Platform) remain, and are harmless.')) {
    & wsl.exe --uninstall | Out-Host
    Say (T 'WSL er fjernet. Start gjerne maskinen på nytt.' 'WSL is removed. Restart the machine if you like.')
  }
}

Say ''
Say (T 'Ferdig.' 'Done.')
if (-not $Purge) { Say (T "Dataene er beholdt. Installerer du på nytt i $Dir, tas de i bruk igjen." "The data is kept. If you reinstall in $Dir, it is picked up again.") }
Say (T 'Dette gjør du selv, om du brukte det:' 'Do these yourself, if you used them:')
Say ("  - " + (T 'Fjern tunnelen og vertsnavnet i Cloudflare Zero Trust (Networks -> Tunnels).' 'Remove the tunnel and hostname in Cloudflare Zero Trust (Networks -> Tunnels).'))
Say ("  - " + (T 'Fjern DNS-postene for domenet ditt.' 'Remove the DNS records for your domain.'))
Say ("  - " + (T 'Si opp lisensen hvis den er betalt.' 'Cancel the license if it is paid.'))
