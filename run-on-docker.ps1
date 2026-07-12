<#
.SYNOPSIS
    Build and run the translator Docker stack locally or on a remote host via SSH.

.DESCRIPTION
    Uses the repo-root Dockerfile (multi-target), docker-compose.yml, and nginx.conf.template.
    Builds both API and web images, then starts the full stack. When --ssh-string is omitted,
    the local Docker daemon is used. When --ssh-string is set, images are built locally,
    exported, transferred to the remote host, loaded there, and compose is started without
    a remote build. When --delete-volume=yes, existing compose volumes are removed before
    the stack is recreated.

.PARAMETER SshString
    SSH config alias for remote Docker (e.g. example). The script prepends "ssh"
    when connecting; do not include "ssh" in the value. When omitted, localhost Docker is used.

.PARAMETER DeleteVolume
    Whether to remove data volumes before starting. Default: no.

.PARAMETER DockerNetwork
    Docker network name attached to the stack. Default: translator-net.

.PARAMETER ApiHost
    API container hostname on the Docker network. Default: translator.

.PARAMETER ApiPort
    API port reachable on the Docker network for the web /api proxy. Default: 8080.

.EXAMPLE
    .\run-on-docker.ps1

.EXAMPLE
    .\run-on-docker.ps1 --delete-volume=yes

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string=myvps

.EXAMPLE
    .\ run-on-docker.ps1 --ssh-string=example --delete-volume=no
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
  .\run-on-docker.ps1 [--ssh-string=<alias>] [--delete-volume=<no|yes>] [--network=<name>] [--api-host=<name>] [--api-port=<port>] [--help]

Arguments:
  --ssh-string=<alias>        SSH config alias for remote Docker (e.g. example)
                              The script prepends "ssh" when connecting; do not include "ssh"
                              in the value. Builds images locally, transfers them to the server,
                              then starts compose remotely. When omitted, localhost Docker is used.
  --delete-volume=<no|yes>    Remove named volumes before starting (default: no)
  --network=<name>            Docker network for the stack (default: translator-net)
  --api-host=<name>           API container hostname on that network (default: translator)
  --api-port=<port>           API port on that network for /api proxy (default: 8080)
  --help, -h                  Show this help message and exit

Examples:
  .\run-on-docker.ps1
  .\run-on-docker.ps1 --help
  .\run-on-docker.ps1 --delete-volume=yes
  .\ run-on-docker.ps1 --network=translator-net --api-port=8080
  .\ run-on-docker.ps1 --ssh-string=example
  .\ run-on-docker.ps1 --ssh-string=example --delete-volume=no

Remote deploy (--ssh-string): builds images locally, exports them, uploads to the
server, loads them there, and starts compose without a remote build.

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

    $index = 0
    while ($index -lt $RemainingArguments.Count) {
        $argument = $RemainingArguments[$index]
        if ($argument -match '^--?(?<name>[\w-]+)(?:=(?<value>.*))?$') {
            $normalizedKey = ($Matches['name'] -replace '-', '_').ToLowerInvariant()
            if ($normalizedKey -in @('help', 'h')) {
                $merged['help'] = $true
                $index++
                continue
            }
            if ($null -ne $Matches['value'] -and $Matches['value'] -ne '') {
                $merged[$normalizedKey] = Remove-SurroundingQuotes -Value $Matches['value']
                $index++
            }
            elseif (($index + 1) -lt $RemainingArguments.Count -and $RemainingArguments[$index + 1] -notmatch '^-') {
                $merged[$normalizedKey] = Remove-SurroundingQuotes -Value $RemainingArguments[$index + 1]
                $index += 2
            }
            else {
                $merged[$normalizedKey] = $true
                $index++
            }
        }
        elseif ($argument -match '^(-h|-help|--help|-\?|/?\?)$') {
            $merged['help'] = $true
            $index++
        }
        else {
            throw "Unknown argument: '$argument'. Run with --help."
        }
    }
    return $merged
}

function Test-Truthy {
    param([string]$Value)

    switch ($Value.ToLowerInvariant()) {
        { $_ -in @('yes', 'true', '1', 'y', 'on') } { return $true }
        default { return $false }
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

function Resolve-SshTarget {
    param([string]$SshString)

    if ([string]::IsNullOrWhiteSpace($SshString)) {
        return [pscustomobject]@{
            IsLocal  = $true
            SshAlias = $null
        }
    }

    $alias = $SshString.Trim()

    if ($alias -match '^(?i)ssh(\s|$)') {
        throw 'Invalid --ssh-string value. Pass only the SSH config alias (e.g. --ssh-string=example). Do not include "ssh".'
    }

    if ([string]::IsNullOrWhiteSpace($alias)) {
        throw 'Invalid --ssh-string value. Example: --ssh-string=example'
    }

    return [pscustomobject]@{
        IsLocal  = $false
        SshAlias = $alias
    }
}

function Invoke-RemoteShell {
    param(
        [pscustomobject]$Target,
        [string]$Command,
        [string]$WorkingDirectory = $null
    )

    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }

    if ($Target.IsLocal) {
        if ($WorkingDirectory) {
            Push-Location $WorkingDirectory
            try { Invoke-Expression $Command | Out-Null }
            finally { Pop-Location }
        }
        else {
            Invoke-Expression $Command | Out-Null
        }
        if ($LASTEXITCODE -ne 0) { throw "Command failed (exit $LASTEXITCODE): $Command" }
        return
    }

    & ssh $Target.SshAlias $remoteCommand
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
}

function Test-DockerCliAvailable {
    param([pscustomobject]$Target = $null)

    if ($null -eq $Target -or $Target.IsLocal) {
        & docker version | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running.' }
        return
    }

    Invoke-RemoteShell -Target $Target -Command 'docker version'
}

function Copy-FileToRemote {
    param(
        [pscustomobject]$Target,
        [string]$LocalPath,
        [string]$RemotePath
    )

    & scp -o StrictHostKeyChecking=accept-new $LocalPath "$($Target.SshAlias):$RemotePath"
    if ($LASTEXITCODE -ne 0) { throw "Failed to copy '$LocalPath' to remote." }
}

function Sync-DeployFilesToRemote {
    param(
        [pscustomobject]$Target,
        [string]$LocalRoot,
        [string]$RemotePath
    )

    Invoke-RemoteShell -Target $Target -Command "mkdir -p '$RemotePath' '$RemotePath/.docker'"

    foreach ($relativePath in $Script:DeploySyncFiles) {
        $localPath = Join-Path $LocalRoot $relativePath
        if (-not (Test-Path $localPath)) {
            throw "Missing deploy file: $relativePath"
        }

        $remoteTarget = if ($relativePath -like '.docker/*') {
            "$RemotePath/$relativePath"
        }
        else {
            "$RemotePath/"
        }

        Copy-FileToRemote -Target $Target -LocalPath $localPath -RemotePath $remoteTarget
    }
}

function Get-StackManifest {
    param([string]$ProjectRoot)

    $manifestPath = Join-Path $ProjectRoot '.docker/stack.manifest.json'
    if (-not (Test-Path $manifestPath)) { return $null }
    return Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
}

function Get-StackImageTags {
    param([string]$ProjectRoot)

    $defaults = @{
        ApiImageTag = 'translator-api:latest'
        WebImageTag = 'translator-web:latest'
    }

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest) {
        if ($manifest.apiImageTag) { $defaults.ApiImageTag = [string]$manifest.apiImageTag }
        elseif ($manifest.imageTag) { $defaults.ApiImageTag = [string]$manifest.imageTag }
        if ($manifest.webImageTag) { $defaults.WebImageTag = [string]$manifest.webImageTag }
    }

    return [pscustomobject]$defaults
}

function Get-ImageArchiveName {
    param([string]$StackName)

    return ($StackName -replace '[^a-zA-Z0-9._-]', '-') + '-images.tar'
}

function Build-LocalDockerImages {
    param([string]$ProjectRoot)

    Push-Location $ProjectRoot
    try {
        & docker compose -f $Script:ComposeFile build
        if ($LASTEXITCODE -ne 0) { throw "docker compose build failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
}

function Export-LocalDockerImages {
    param(
        [string[]]$ImageTags,
        [string]$ArchivePath
    )

    $parentDirectory = Split-Path -Parent $ArchivePath
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $ArchivePath) {
        Remove-Item -LiteralPath $ArchivePath -Force
    }

    & docker save -o $ArchivePath @ImageTags
    if ($LASTEXITCODE -ne 0) { throw "docker save failed (exit $LASTEXITCODE)" }
}

function Transfer-DockerImagesToRemote {
    param(
        [pscustomobject]$Target,
        [string[]]$ImageTags,
        [string]$RemotePath,
        [string]$StackName
    )

    $archiveName = Get-ImageArchiveName -StackName $StackName
    $localArchive = Join-Path $Script:LocalDeployDir $archiveName
    $remoteArchive = "$RemotePath/$archiveName"

    try {
        Export-LocalDockerImages -ImageTags $ImageTags -ArchivePath $localArchive

        $tarSizeMb = [math]::Round((Get-Item $localArchive).Length / 1MB, 1)
        Write-Host "Transferring images ($tarSizeMb MB) to remote host..." -ForegroundColor Cyan
        Copy-FileToRemote -Target $Target -LocalPath $localArchive -RemotePath $remoteArchive

        Write-Host 'Loading images on remote host...' -ForegroundColor Cyan
        Invoke-RemoteShell -Target $Target -Command "docker load -i '$remoteArchive' && rm -f '$remoteArchive'"
        Write-Host 'Images loaded on remote host.' -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $localArchive) {
            Remove-Item -LiteralPath $localArchive -Force -ErrorAction SilentlyContinue
        }
    }
}
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
        [string]$ApiPortNumber,
        [bool]$PublishHostPorts = $true
    )

    $env:DOCKER_NETWORK = $NetworkName
    $env:API_HOST = $ApiHostName
    $env:API_PORT = $ApiPortNumber

    if ($PublishHostPorts) {
        Remove-Item Env:API_PUBLISH_PORT -ErrorAction SilentlyContinue
        Remove-Item Env:WEB_PUBLISH_PORT -ErrorAction SilentlyContinue
        Remove-Item Env:POSTGRES_PUBLISH_PORT -ErrorAction SilentlyContinue
    }
    else {
        $env:API_PUBLISH_PORT = ''
        $env:WEB_PUBLISH_PORT = ''
        $env:POSTGRES_PUBLISH_PORT = ''
    }
}

function Get-RemoteComposeEnvironmentPrefix {
    param(
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber,
        [bool]$PublishHostPorts = $false
    )

    $prefix = "DOCKER_NETWORK='$NetworkName' API_HOST='$ApiHostName' API_PORT='$ApiPortNumber' "
    if (-not $PublishHostPorts) {
        $prefix += "API_PUBLISH_PORT='' WEB_PUBLISH_PORT='' POSTGRES_PUBLISH_PORT='' "
    }
    return $prefix
}

function Ensure-DockerNetwork {
    param(
        [pscustomobject]$Target,
        [string]$NetworkName,
        [string]$WorkingDirectory
    )

    if ($Target.IsLocal) {
        $existingNetworks = docker network ls --format '{{.Name}}'
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to list Docker networks. Is Docker running?'
        }
        if ($existingNetworks -notcontains $NetworkName) {
            docker network create $NetworkName | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create Docker network '$NetworkName'."
            }
        }
        return
    }

    $createCommand = "docker network inspect '$NetworkName' >/dev/null 2>&1 || docker network create '$NetworkName'"
    try {
        Invoke-RemoteShell -Target $Target -Command $createCommand -WorkingDirectory $WorkingDirectory
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
        [pscustomobject]$Target,
        [string]$WorkingDirectory,
        [bool]$RemoveVolumes,
        [bool]$Build,
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

    if ($Target.IsLocal) {
        Push-Location $WorkingDirectory
        try {
            Set-ComposeEnvironment -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber -PublishHostPorts:$Target.IsLocal
            Invoke-Expression $composeDown | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
            }
            Invoke-Expression $composeUp | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
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
        Invoke-RemoteShell -Target $Target -Command $composeDown -WorkingDirectory $WorkingDirectory
    }
    catch {
        Write-Host 'Remote compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
    }

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber -PublishHostPorts:$Target.IsLocal
    Invoke-RemoteShell -Target $Target -Command "${envPrefix}$composeUp" -WorkingDirectory $WorkingDirectory
}

if ($Help -or $SshString -match '^(-h|-help|--help|-\?|/?\?)$') {
    Show-RunOnDockerHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$cliArgs = Merge-CliArguments -BoundParameters $PSBoundParameters -RemainingArguments $RemainingArguments
if ($cliArgs['help']) {
    Show-RunOnDockerHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$sshStringValue = if ($cliArgs['ssh_string']) { [string]$cliArgs['ssh_string'] } else { [string]$SshString }
$sshStringValue = Normalize-CliParameterValue -Name 'ssh_string' -Value $sshStringValue
$deleteVolumeValue = if ($cliArgs['delete_volume']) { [string]$cliArgs['delete_volume'] } else { [string]$DeleteVolume }
$deleteVolumeValue = Normalize-CliParameterValue -Name 'delete_volume' -Value $deleteVolumeValue
$networkValue = if ($cliArgs['network']) { [string]$cliArgs['network'] } else { [string]$DockerNetwork }
$networkValue = Normalize-CliParameterValue -Name 'network' -Value $networkValue
$removeVolumes = Test-Truthy -Value $deleteVolumeValue

$ProjectRoot = $PSScriptRoot
$manifestDefaults = Get-DockerManifestDefaults -ProjectRoot $ProjectRoot
$apiHostValue = if ($cliArgs['api_host']) { [string]$cliArgs['api_host'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiHost)) { [string]$ApiHost } else { $manifestDefaults.ApiHost }
$apiHostValue = Normalize-CliParameterValue -Name 'api_host' -Value $apiHostValue
$apiPortValue = if ($cliArgs['api_port']) { [string]$cliArgs['api_port'] } elseif (-not [string]::IsNullOrWhiteSpace($ApiPort)) { [string]$ApiPort } else { $manifestDefaults.ApiPort }
$apiPortValue = Normalize-CliParameterValue -Name 'api_port' -Value $apiPortValue

if ([string]::IsNullOrWhiteSpace($networkValue)) {
    throw 'Invalid --network value. Example: --network=translator-net'
}
if ([string]::IsNullOrWhiteSpace($apiHostValue)) {
    throw 'Invalid --api-host value. Example: --api-host=translator'
}
Test-PortNumber -Value $apiPortValue -ParameterName '--api-port'

$target = Resolve-SshTarget -SshString $sshStringValue
$workDir = if ($target.IsLocal) { $ProjectRoot } else { Get-RemoteWorkDir -ProjectRoot $ProjectRoot }
$imageTags = Get-StackImageTags -ProjectRoot $ProjectRoot
$stackManifest = Get-StackManifest -ProjectRoot $ProjectRoot
$stackName = if ($stackManifest -and $stackManifest.stackName) { [string]$stackManifest.stackName } else { 'translator' }

$targetLabel = if ($target.IsLocal) { 'localhost' } else { "ssh $($target.SshAlias)" }
$volumeAction = if ($removeVolumes) { 'removing volumes' } else { 'keeping volumes' }
$totalSteps = if ($target.IsLocal) { 4 } else { 7 }

try {
    $deployMode = if ($target.IsLocal) { 'local Docker' } else { 'local build + image transfer' }
    Write-Host ("Target: {0} ({1}) | network: {2} | api: {3}:{4} | images: {5}, {6} | {7}" -f `
        $targetLabel, $deployMode, $networkValue, $apiHostValue, $apiPortValue, `
        $imageTags.ApiImageTag, $imageTags.WebImageTag, $volumeAction) -ForegroundColor Cyan

    Write-RunStep -Step 1 -Total $totalSteps -Message 'Checking Docker files'
    Test-DockerComposeFile -ProjectRoot $ProjectRoot
    Test-DockerCliAvailable -Target $target

    Write-RunStep -Step 2 -Total $totalSteps -Message 'Building API and web images'
    Build-LocalDockerImages -ProjectRoot $ProjectRoot

    if ($target.IsLocal) {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Target $target -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Target $target -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -Build:$false -NetworkName $networkValue -ApiHostName $apiHostValue -ApiPortNumber $apiPortValue
    }
    else {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Syncing compose files to $targetLabel"
        Sync-DeployFilesToRemote -Target $target -LocalRoot $ProjectRoot -RemotePath $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message 'Transferring images to remote host'
        Transfer-DockerImagesToRemote -Target $target -ImageTags @($imageTags.ApiImageTag, $imageTags.WebImageTag) -RemotePath $workDir -StackName $stackName

        Write-RunStep -Step 5 -Total $totalSteps -Message 'Checking remote Docker'
        Test-DockerCliAvailable -Target $target

        Write-RunStep -Step 6 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Target $target -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 7 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Target $target -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -Build:$false -NetworkName $networkValue -ApiHostName $apiHostValue -ApiPortNumber $apiPortValue
    }

    Write-Progress -Activity 'translator Docker run' -Completed -Status 'Done'
    Write-Host ''
    Write-Host ("Run complete on {0}. Images built locally and deployed without remote build." -f $SshAlias) -ForegroundColor Green
    Write-Host ("Remote path: {0}" -f $Script:RemoteProjectPath) -ForegroundColor Green
}

    if ($target.IsLocal) {
        Write-Host 'Stack is running on localhost.' -ForegroundColor Green
        Write-Host '  Web UI: http://localhost:8082' -ForegroundColor Green
        Write-Host '  API:    http://localhost:8080' -ForegroundColor Green
    }
    else {
        Write-Host "Stack is running on remote host at $workDir (network: $networkValue, api: ${apiHostValue}:${apiPortValue})." -ForegroundColor Green
        Write-Host ("Images were built locally and deployed to {0} without a remote build." -f $target.SshAlias) -ForegroundColor Green
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
