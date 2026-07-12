<#
.SYNOPSIS
    Build and run the translator Docker stack locally or on a remote host via SSH.

.DESCRIPTION
    Uses docker-compose.yml from the project root. Builds API and web images, then
    starts postgres, api, and web on an external Docker network. When --ssh-string
    is omitted, Docker on localhost is used. When --ssh-string is set, images are
    built locally, exported, transferred to the remote host, loaded there, and
    started without rebuilding on the server. When --delete-volume=yes, existing
    containers and named volumes are removed before start.

.EXAMPLE
    .\run-on-docker.ps1

.EXAMPLE
    .\run-on-docker.ps1 --delete-volume=yes

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string=myvps

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string=production --delete-volume=no
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ProjectRoot = $PSScriptRoot
$Script:ComposeFile = 'docker-compose.yml'
$Script:LocalDeployDir = Join-Path $Script:ProjectRoot '.deploy'
$Script:DeploySyncFiles = @(
    'docker-compose.yml',
    'Dockerfile',
    'nginx.conf.template',
    '.dockerignore',
    '.docker/stack.manifest.json'
)

function Get-StackManifest {
    param([string]$ProjectRoot)

    $manifestPath = Join-Path $ProjectRoot '.docker/stack.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return $null
    }

    return Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Get-ManifestValue {
    param(
        $Manifest,
        [string]$Property,
        [string]$Default
    )

    if ($null -eq $Manifest) {
        return $Default
    }

    if ($Manifest.PSObject.Properties.Name -contains $Property -and $null -ne $Manifest.$Property) {
        return [string]$Manifest.$Property
    }

    return $Default
}

function Get-RemoteProjectPath {
    param($Manifest)

    $stackName = Get-ManifestValue -Manifest $Manifest -Property 'stackName' -Default 'translator'
    return "/opt/docker/$stackName"
}

function Initialize-RunSettings {
    $manifest = Get-StackManifest -ProjectRoot $Script:ProjectRoot
    $stackName = (Get-ManifestValue -Manifest $manifest -Property 'stackName' -Default 'translator') -replace '[^a-zA-Z0-9._-]', '-'

    $Script:RemoteProjectPath = Get-RemoteProjectPath -Manifest $manifest
    $Script:ApiImageName = Get-ManifestValue -Manifest $manifest -Property 'apiImageTag' -Default 'translator-api:latest'
    $Script:WebImageName = Get-ManifestValue -Manifest $manifest -Property 'webImageTag' -Default 'translator-web:latest'
    $Script:ImageArchiveName = "$stackName-images.tar"
    $Script:DockerNetwork = 'translator-net'
    $Script:ApiHost = Get-ManifestValue -Manifest $manifest -Property 'containerName' -Default 'translator'
    $Script:ApiPort = Get-ManifestValue -Manifest $manifest -Property 'internalPort' -Default '8080'
    $Script:WebPublishPort = Get-ManifestValue -Manifest $manifest -Property 'webPublishPort' -Default '8082'
    $Script:ApiPublishPort = Get-ManifestValue -Manifest $manifest -Property 'apiPublishPort' -Default '8080'
}

function Show-RunOnDockerHelp {
    Write-Host @'
translator Docker run - build API + web images and start the Compose stack

Usage:
  .\run-on-docker.ps1 [--ssh-string=<alias>] [--delete-volume=<no|yes>] [--network=<name>] [--api-host=<name>] [--api-port=<port>]

Arguments:
  --ssh-string=<alias>        SSH config alias for remote Docker (e.g. myvps)
                              The script prepends "ssh" when connecting; do not include "ssh"
                              in the value. Builds locally, transfers images, then starts
                              the stack remotely. When omitted, localhost Docker is used.
  --delete-volume=<no|yes>    Remove named volumes before starting (default: no)
  --network=<name>            Docker network for the stack (default: translator-net)
  --api-host=<name>           API container hostname on that network (default: translator)
  --api-port=<port>           API port on that network for /api proxy (default: 8080)

Examples:
  .\run-on-docker.ps1
  .\run-on-docker.ps1 --delete-volume=yes
  .\run-on-docker.ps1 --ssh-string=myvps
  .\run-on-docker.ps1 --ssh-string=production --delete-volume=no

Web UI: http://localhost:8082  |  API: http://localhost:8080
'@ -ForegroundColor Cyan
}

function ConvertTo-RunArguments {
    param([string[]]$RawArguments)

    $parsed = @{
        ssh_string    = $null
        delete_volume = 'no'
        network       = $null
        api_host      = $null
        api_port      = $null
        help          = $false
    }

    foreach ($argument in $RawArguments) {
        if ($argument -match '^--(?<name>[\w-]+)(?:=(?<value>.*))?$') {
            $key = ($Matches['name'] -replace '-', '_').ToLowerInvariant()
            $value = if ($Matches.ContainsKey('value')) { $Matches['value'] } else { 'true' }

            switch ($key) {
                'help' { $parsed['help'] = $true }
                'ssh_string' { $parsed['ssh_string'] = $value.Trim() }
                'delete_volume' { $parsed['delete_volume'] = $value.Trim().ToLowerInvariant() }
                'network' { $parsed['network'] = $value.Trim() }
                'api_host' { $parsed['api_host'] = $value.Trim() }
                'api_port' { $parsed['api_port'] = $value.Trim() }
                default { throw "Unknown argument: --$($Matches['name']). Run with --help." }
            }
        }
        elseif ($argument -match '^-(?<flag>[h?])$') {
            $parsed['help'] = $true
        }
        else {
            throw "Unknown argument: $argument. Run with --help."
        }
    }

    if ($parsed['delete_volume'] -notin @('no', 'yes', 'false', 'true', '0', '1')) {
        throw "Invalid --delete-volume value '$($parsed['delete_volume'])'. Allowed: no, yes."
    }

    return $parsed
}

function Test-DeleteVolumeEnabled {
    param([string]$Value)

    return $Value -in @('yes', 'true', '1')
}

function Resolve-SshAlias {
    param([string]$SshString)

    $alias = $SshString.Trim()

    if ($alias -match '^(?i)ssh(\s|$)') {
        throw 'Invalid --ssh-string value. Pass only the SSH config alias (e.g. --ssh-string=myvps). Do not include "ssh".'
    }

    if ([string]::IsNullOrWhiteSpace($alias)) {
        throw 'Invalid --ssh-string value. Example: --ssh-string=myvps'
    }

    return $alias
}

function Test-PortNumber {
    param(
        [string]$Value,
        [string]$ParameterName
    )

    if ($Value -notmatch '^\d+$') {
        throw "Invalid $ParameterName value '$Value'. Use a numeric port between 1 and 65535."
    }

    $port = [int]$Value
    if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid $ParameterName value '$Value'. Use a port between 1 and 65535."
    }
}

function Write-RunStep {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Message
    )

    $percent = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity 'translator Docker run' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Yellow
}

function Test-DockerCliAvailable {
    param([string]$CommandPrefix = '')

    $checkCommand = if ($CommandPrefix) { "$CommandPrefix docker version" } else { 'docker version' }
    Invoke-Expression $checkCommand | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw 'Docker CLI is not available or not running.'
    }
}

function Test-DockerComposeFiles {
    foreach ($relativePath in $Script:DeploySyncFiles) {
        $path = Join-Path $Script:ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing deploy file: $relativePath"
        }
    }
}

function Invoke-RemoteShell {
    param(
        [string]$SshAlias,
        [string]$Command,
        [string]$WorkingDirectory = $null
    )

    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }
    & ssh $SshAlias $remoteCommand

    if ($LASTEXITCODE -ne 0) {
        throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand"
    }
}

function Set-ComposeEnvironment {
    param(
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    $env:DOCKER_NETWORK = $NetworkName
    $env:API_HOST = $ApiHostName
    $env:API_PORT = $ApiPortNumber
}

function Get-RemoteComposeEnvironmentPrefix {
    param(
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    return "DOCKER_NETWORK='$NetworkName' API_HOST='$ApiHostName' API_PORT='$ApiPortNumber' "
}

function Ensure-DockerNetwork {
    param(
        [string]$CommandPrefix = '',
        [string]$NetworkName
    )

    $inspectCommand = if ($CommandPrefix) {
        "$CommandPrefix docker network inspect '$NetworkName'"
    }
    else {
        "docker network inspect '$NetworkName'"
    }

    Invoke-Expression "$inspectCommand >/dev/null 2>&1" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        return
    }

    $createCommand = if ($CommandPrefix) {
        "$CommandPrefix docker network create '$NetworkName'"
    }
    else {
        "docker network create '$NetworkName'"
    }

    Invoke-Expression $createCommand | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create Docker network '$NetworkName'."
    }
}

function Build-LocalDockerImages {
    Push-Location $Script:ProjectRoot
    try {
        docker compose -f $Script:ComposeFile build
        if ($LASTEXITCODE -ne 0) {
            throw 'Local docker compose build failed.'
        }
    }
    finally {
        Pop-Location
    }
}

function Export-LocalDockerImages {
    param([string]$ArchivePath)

    $parentDirectory = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }

    docker save $Script:ApiImageName $Script:WebImageName -o $ArchivePath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to export images '$($Script:ApiImageName)' and '$($Script:WebImageName)'."
    }
}

function Sync-DeployFilesToRemote {
    param([string]$SshAlias)

    & ssh $SshAlias "mkdir -p '$Script:RemoteProjectPath' '$Script:RemoteProjectPath/.docker'"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create remote directory: $Script:RemoteProjectPath"
    }

    foreach ($relativePath in $Script:DeploySyncFiles) {
        $localPath = Join-Path $Script:ProjectRoot $relativePath
        $remoteDestination = if ($relativePath -like '.docker/*') {
            '{0}:{1}/{2}' -f $SshAlias, $Script:RemoteProjectPath, $relativePath
        }
        else {
            '{0}:{1}/' -f $SshAlias, $Script:RemoteProjectPath
        }

        & scp -o StrictHostKeyChecking=accept-new $localPath $remoteDestination
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to copy '$relativePath' to remote host."
        }
    }
}

function Transfer-ImagesToRemote {
    param(
        [string]$SshAlias,
        [string]$ArchivePath
    )

    $remoteArchivePath = '{0}:{1}/{2}' -f $SshAlias, $Script:RemoteProjectPath, $Script:ImageArchiveName
    & scp -o StrictHostKeyChecking=accept-new $ArchivePath $remoteArchivePath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to transfer image archive to remote host.'
    }
}

function Import-RemoteDockerImages {
    param([string]$SshAlias)

    $remoteArchivePath = '{0}/{1}' -f $Script:RemoteProjectPath, $Script:ImageArchiveName
    Invoke-RemoteShell -SshAlias $SshAlias -Command "docker load -i '$remoteArchivePath' && rm -f '$remoteArchivePath'"
}

function Invoke-DockerComposeRun {
    param(
        [string]$CommandPrefix = '',
        [string]$WorkingDirectory = $Script:ProjectRoot,
        [bool]$DeleteVolume = $false,
        [bool]$Build = $true,
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber
    $composeDown = if ($CommandPrefix) {
        "$CommandPrefix docker compose -f $Script:ComposeFile down"
    }
    else {
        "docker compose -f $Script:ComposeFile down"
    }

    if ($DeleteVolume) {
        $composeDown += ' -v'
    }

    $composeUp = if ($CommandPrefix) {
        "${envPrefix}$CommandPrefix docker compose -f $Script:ComposeFile up -d"
    }
    else {
        Set-ComposeEnvironment -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber
        "docker compose -f $Script:ComposeFile up -d"
    }

    if ($Build) {
        $composeUp += ' --build'
    }

    Push-Location $WorkingDirectory
    try {
        if (-not $CommandPrefix) {
            Set-ComposeEnvironment -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber
        }

        Invoke-Expression $composeDown | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
        }

        Invoke-Expression $composeUp
        if ($LASTEXITCODE -ne 0) {
            throw 'docker compose up failed.'
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-LocalDockerRun {
    param(
        [bool]$DeleteVolume,
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    Write-RunStep -Step 1 -Total 4 -Message 'Checking local Docker and deploy files'
    Test-DockerComposeFiles
    Test-DockerCliAvailable

    Write-RunStep -Step 2 -Total 4 -Message "Ensuring Docker network '$NetworkName'"
    Ensure-DockerNetwork -NetworkName $NetworkName

    Write-RunStep -Step 3 -Total 4 -Message $(if ($DeleteVolume) { 'Stopping stack and removing volumes' } else { 'Stopping stack (keeping volumes)' })
    Invoke-DockerComposeRun -DeleteVolume:$DeleteVolume -Build -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber

    Write-RunStep -Step 4 -Total 4 -Message 'Stack started'
    Write-Progress -Activity 'translator Docker run' -Completed -Status 'Done'
    Write-Host ''
    Write-Host "Run complete. Web UI: http://localhost:$Script:WebPublishPort  |  API: http://localhost:$Script:ApiPublishPort" -ForegroundColor Green
}

function Invoke-RemoteDockerRun {
    param(
        [string]$SshAlias,
        [bool]$DeleteVolume,
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    $archivePath = Join-Path $Script:LocalDeployDir $Script:ImageArchiveName

    Write-RunStep -Step 1 -Total 7 -Message 'Checking local Docker and deploy files'
    Test-DockerComposeFiles
    Test-DockerCliAvailable

    Write-RunStep -Step 2 -Total 7 -Message "Building images locally ($($Script:ApiImageName), $($Script:WebImageName))"
    Build-LocalDockerImages

    Write-RunStep -Step 3 -Total 7 -Message 'Exporting image archive'
    Export-LocalDockerImages -ArchivePath $archivePath

    Write-RunStep -Step 4 -Total 7 -Message "Checking Docker on $SshAlias"
    Test-DockerCliAvailable -CommandPrefix "ssh $SshAlias"

    Write-RunStep -Step 5 -Total 7 -Message "Transferring images and deploy files to $SshAlias"
    Sync-DeployFilesToRemote -SshAlias $SshAlias
    Transfer-ImagesToRemote -SshAlias $SshAlias -ArchivePath $archivePath
    Import-RemoteDockerImages -SshAlias $SshAlias

    Write-RunStep -Step 6 -Total 7 -Message "Ensuring Docker network '$NetworkName' on $SshAlias"
    Ensure-DockerNetwork -CommandPrefix "ssh $SshAlias" -NetworkName $NetworkName

    Write-RunStep -Step 7 -Total 7 -Message $(if ($DeleteVolume) { 'Stopping remote stack and removing volumes' } else { 'Stopping remote stack (keeping volumes)' })
    $composeDown = "docker compose -f $Script:ComposeFile down"
    if ($DeleteVolume) {
        $composeDown += ' -v'
    }

    try {
        Invoke-RemoteShell -SshAlias $SshAlias -Command $composeDown -WorkingDirectory $Script:RemoteProjectPath
    }
    catch {
        Write-Host 'Remote compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
    }

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber
    Invoke-RemoteShell -SshAlias $SshAlias -Command "${envPrefix}docker compose -f $Script:ComposeFile up -d" -WorkingDirectory $Script:RemoteProjectPath

    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Write-Progress -Activity 'translator Docker run' -Completed -Status 'Done'
    Write-Host ''
    Write-Host ("Run complete on {0}. Images built locally and deployed without remote build." -f $SshAlias) -ForegroundColor Green
    Write-Host ("Remote path: {0}" -f $Script:RemoteProjectPath) -ForegroundColor Green
}

Initialize-RunSettings

$argumentMap = ConvertTo-RunArguments -RawArguments $args
if ($argumentMap['help']) {
    Show-RunOnDockerHelp
    exit 0
}

$deleteVolume = Test-DeleteVolumeEnabled -Value $argumentMap['delete_volume']
$sshString = $argumentMap['ssh_string']
$networkName = if ($argumentMap['network']) { $argumentMap['network'] } else { $Script:DockerNetwork }
$apiHostName = if ($argumentMap['api_host']) { $argumentMap['api_host'] } else { $Script:ApiHost }
$apiPortNumber = if ($argumentMap['api_port']) { $argumentMap['api_port'] } else { $Script:ApiPort }

if ([string]::IsNullOrWhiteSpace($networkName)) {
    throw 'Invalid --network value. Example: --network=translator-net'
}
if ([string]::IsNullOrWhiteSpace($apiHostName)) {
    throw 'Invalid --api-host value. Example: --api-host=translator'
}
Test-PortNumber -Value $apiPortNumber -ParameterName '--api-port'

try {
    if ([string]::IsNullOrWhiteSpace($sshString)) {
        Write-Host 'Target: localhost Docker' -ForegroundColor Cyan
        Invoke-LocalDockerRun -DeleteVolume:$deleteVolume -NetworkName $networkName -ApiHostName $apiHostName -ApiPortNumber $apiPortNumber
    }
    else {
        $sshAlias = Resolve-SshAlias -SshString $sshString
        Write-Host ("Target: remote Docker via ssh {0} (local build + image transfer)" -f $sshAlias) -ForegroundColor Cyan
        Invoke-RemoteDockerRun -SshAlias $sshAlias -DeleteVolume:$deleteVolume -NetworkName $networkName -ApiHostName $apiHostName -ApiPortNumber $apiPortNumber
    }
}
catch {
    Write-Progress -Activity 'translator Docker run' -Completed -Status 'Failed'
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-RunOnDockerHelp
    exit 1
}
