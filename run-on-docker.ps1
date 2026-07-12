<#
.SYNOPSIS
    Build and run the translator API + web UI stack with Docker Compose locally or over SSH.

.DESCRIPTION
    Uses the repo-root Dockerfile (multi-target), docker-compose.yml, and nginx.conf.template.
    Builds both API and web images, then starts the full stack. When --ssh-string is omitted,
    the local Docker daemon is used. When --ssh-string is set, images are built locally,
    exported, transferred to the remote host, loaded there, and compose is started without
    a remote build. When --delete-volume=yes, existing compose volumes are removed before
    the stack is recreated.

.PARAMETER SshString
    Remote connection string, e.g. "ssh server-name", "host@user@password",
    or "host@port@user@password". When omitted, localhost Docker is used.

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
    .\run-on-docker.ps1 --network=translator-net --api-host=translator --api-port=8080

.EXAMPLE
    .\run-on-docker.ps1 --ssh-string="ssh myvps"
#>
[CmdletBinding()]
param(
    [Alias('ssh-string')]
    [string]$SshString,
    [Alias('delete-volume')]
    [string]$DeleteVolume = 'no',
    [Alias('network')]
    [string]$DockerNetwork = 'translator-net',
    [Alias('api-host')]
    [string]$ApiHost,
    [Alias('api-port')]
    [string]$ApiPort,
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ComposeFile = 'docker-compose.yml'
$Script:LocalDeployDir = Join-Path $PSScriptRoot '.deploy'
$Script:DeploySyncFiles = @(
    'docker-compose.yml',
    'Dockerfile',
    'nginx.conf.template',
    '.dockerignore',
    '.docker/stack.manifest.json'
)

function Show-RunOnDockerHelp {
    Write-Host @'
translator Docker run - build API + web images and start the Compose stack

Usage:
  .\run-on-docker.ps1 [--ssh-string=<connection>] [--delete-volume=<no|yes>] [--network=<name>] [--api-host=<name>] [--api-port=<port>] [--help]

Arguments:
  --ssh-string=<connection>   Remote target, e.g. "ssh server-name",
                              host@user@password, or host@port@user@password.
                              Builds images locally, transfers them to the server,
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
  .\run-on-docker.ps1 --network=translator-net --api-port=8080
  .\run-on-docker.ps1 --ssh-string="ssh myvps"

Requires docker-compose.yml and Dockerfile in the repo root.
Web UI: http://localhost:8082  |  API: http://localhost:8080
'@ -ForegroundColor Cyan
}

function Remove-SurroundingQuotes {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }

    $Value = $Value.Trim()
    if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
        return $Value.Substring(1, $Value.Length - 2).Trim()
    }
    return $Value
}

function Normalize-CliParameterValue {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }

    $Value = Remove-SurroundingQuotes -Value $Value.Trim()
    if ($Value -match '^--?(?<param>[\w-]+)(?:=(?<rest>.*))?$') {
        $paramKey = ($Matches['param'] -replace '-', '_').ToLowerInvariant()
        $nameKey = ($Name -replace '-', '_').ToLowerInvariant()
        if ($paramKey -eq $nameKey) {
            if ($null -ne $Matches['rest'] -and $Matches['rest'] -ne '') {
                return Remove-SurroundingQuotes -Value $Matches['rest']
            }
            return $null
        }
    }
    return $Value
}

function Merge-CliArguments {
    param([hashtable]$BoundParameters, [string[]]$RemainingArguments)

    if ($null -eq $RemainingArguments) {
        $RemainingArguments = @()
    }
    else {
        $RemainingArguments = @($RemainingArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $merged = @{}
    foreach ($key in $BoundParameters.Keys) {
        $normalizedKey = ([regex]::Replace($key, '([a-z0-9])([A-Z])', '$1_$2')).ToLowerInvariant()
        if ($normalizedKey -in @('remainingarguments', 'help')) { continue }
        if ($null -eq $BoundParameters[$key] -or $BoundParameters[$key] -eq '') { continue }

        $normalizedValue = Normalize-CliParameterValue -Name $normalizedKey -Value ([string]$BoundParameters[$key])
        if ($null -ne $normalizedValue -and $normalizedValue -ne '') {
            $merged[$normalizedKey] = $normalizedValue
        }
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
        elseif ($argument -match '^(-h|-help|--help|-\?|/\?)$') {
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

function Resolve-SshProfile {
    param([string]$ConnectionString)

    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return [pscustomobject]@{
            Mode     = 'local'
            IsLocal  = $true
            Server   = $null
            Username = $null
            Password = $null
            Port     = 22
            SshAlias = $null
        }
    }

    $ConnectionString = $ConnectionString.Trim()

    if ($ConnectionString -match '^(?i)ssh\s+(?<alias>.+)$') {
        return [pscustomobject]@{
            Mode     = 'ssh-alias'
            IsLocal  = $false
            Server   = $null
            Username = $null
            Password = $null
            Port     = 22
            SshAlias = $Matches['alias'].Trim()
        }
    }

    $parts = $ConnectionString -split '@', 4
    if ($parts.Count -eq 4) {
        return [pscustomobject]@{
            Mode     = 'remote-password'
            IsLocal  = $false
            Server   = $parts[0]
            Port     = [int]$parts[1]
            Username = $parts[2]
            Password = $parts[3]
            SshAlias = $null
        }
    }
    if ($parts.Count -eq 3) {
        return [pscustomobject]@{
            Mode     = 'remote-password'
            IsLocal  = $false
            Server   = $parts[0]
            Port     = 22
            Username = $parts[1]
            Password = $parts[2]
            SshAlias = $null
        }
    }

    throw "Invalid --ssh-string '$ConnectionString'. Use server@port@user@password, server@user@password, or 'ssh <alias>'."
}

function Ensure-PoshSshModule {
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw 'Posh-SSH is required for password auth. Install-Module Posh-SSH -Scope CurrentUser'
    }
    Import-Module Posh-SSH -ErrorAction Stop
}

function Invoke-RemoteShell {
    param(
        [pscustomobject]$Profile,
        [string]$Command,
        [string]$WorkingDirectory = $null
    )

    $remoteCommand = if ($WorkingDirectory) { "cd '$WorkingDirectory' && $Command" } else { $Command }

    if ($Profile.IsLocal) {
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

    if ($Profile.Mode -eq 'ssh-alias') {
        & ssh $Profile.SshAlias $remoteCommand
    }
    elseif ([string]::IsNullOrWhiteSpace($Profile.Password)) {
        & ssh -p $Profile.Port -o StrictHostKeyChecking=accept-new "$($Profile.Username)@$($Profile.Server)" $remoteCommand
    }
    else {
        Ensure-PoshSshModule
        $credential = New-Object System.Management.Automation.PSCredential(
            $Profile.Username,
            (ConvertTo-SecureString $Profile.Password -AsPlainText -Force)
        )
        $session = New-SSHSession -ComputerName $Profile.Server -Port $Profile.Port -Credential $credential -AcceptKey -ErrorAction Stop
        try {
            $result = Invoke-SSHCommand -SessionId $session.SessionId -Command $remoteCommand -TimeOut 900
            if ($result.ExitStatus -ne 0) { throw "Remote command failed: $($result.Error)`n$remoteCommand" }
            if ($result.Output) { Write-Output ($result.Output -join [Environment]::NewLine) }
        }
        finally { Remove-SSHSession -SessionId $session.SessionId | Out-Null }
        return
    }

    if ($LASTEXITCODE -ne 0) { throw "Remote command failed (exit $LASTEXITCODE): $remoteCommand" }
}

function Test-DockerCliAvailable {
    param([pscustomobject]$Profile = $null)

    if ($null -eq $Profile -or $Profile.IsLocal) {
        & docker version | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Docker CLI is not available or not running.' }
        return
    }

    Invoke-RemoteShell -Profile $Profile -Command 'docker version'
}

function Copy-FileToRemote {
    param(
        [pscustomobject]$Profile,
        [string]$LocalPath,
        [string]$RemotePath
    )

    if ($Profile.Mode -eq 'ssh-alias') {
        & scp -o StrictHostKeyChecking=accept-new $LocalPath "$($Profile.SshAlias):$RemotePath"
        if ($LASTEXITCODE -ne 0) { throw "Failed to copy '$LocalPath' to remote." }
        return
    }

    $sshTarget = "$($Profile.Username)@$($Profile.Server)"
    if ([string]::IsNullOrWhiteSpace($Profile.Password)) {
        & scp -P $Profile.Port -o StrictHostKeyChecking=accept-new $LocalPath "${sshTarget}:$RemotePath"
        if ($LASTEXITCODE -ne 0) { throw "Failed to copy '$LocalPath' to remote." }
        return
    }

    Ensure-PoshSshModule
    $credential = New-Object System.Management.Automation.PSCredential(
        $Profile.Username,
        (ConvertTo-SecureString $Profile.Password -AsPlainText -Force)
    )
    Set-SCPItem -ComputerName $Profile.Server -Port $Profile.Port -Credential $credential -Path $LocalPath -Destination $RemotePath -AcceptKey -Force
}

function Sync-DeployFilesToRemote {
    param(
        [pscustomobject]$Profile,
        [string]$LocalRoot,
        [string]$RemotePath
    )

    Invoke-RemoteShell -Profile $Profile -Command "mkdir -p '$RemotePath' '$RemotePath/.docker'"

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

        Copy-FileToRemote -Profile $Profile -LocalPath $localPath -RemotePath $remoteTarget
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
        [pscustomobject]$Profile,
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
        Copy-FileToRemote -Profile $Profile -LocalPath $localArchive -RemotePath $remoteArchive

        Write-Host 'Loading images on remote host...' -ForegroundColor Cyan
        Invoke-RemoteShell -Profile $Profile -Command "docker load -i '$remoteArchive' && rm -f '$remoteArchive'"
        Write-Host 'Images loaded on remote host.' -ForegroundColor Green
    }
    finally {
        if (Test-Path -LiteralPath $localArchive) {
            Remove-Item -LiteralPath $localArchive -Force -ErrorAction SilentlyContinue
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

function Get-DockerManifestDefaults {
    param([string]$ProjectRoot)

    $defaults = @{
        ApiHost = 'translator'
        ApiPort = '8080'
    }

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if (-not $manifest) { return $defaults }

    if ($manifest.containerName) { $defaults.ApiHost = [string]$manifest.containerName }
    if ($manifest.internalPort) { $defaults.ApiPort = [string]$manifest.internalPort }
    elseif ($manifest.apiPort) { $defaults.ApiPort = [string]$manifest.apiPort }

    return $defaults
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

function Get-RemoteWorkDir {
    param([string]$ProjectRoot)

    $manifest = Get-StackManifest -ProjectRoot $ProjectRoot
    if ($manifest -and $manifest.stackName) {
        return "/opt/docker/$($manifest.stackName)"
    }
    return '/opt/docker/translator'
}

function Test-DockerComposeFile {
    param([string]$ProjectRoot)

    $composePath = Join-Path $ProjectRoot $Script:ComposeFile
    if (-not (Test-Path $composePath)) {
        throw "Missing $Script:ComposeFile in the repo root."
    }

    $dockerfilePath = Join-Path $ProjectRoot 'Dockerfile'
    if (-not (Test-Path $dockerfilePath)) {
        throw 'Missing Dockerfile in the repo root.'
    }

    $nginxTemplatePath = Join-Path $ProjectRoot 'nginx.conf.template'
    if (-not (Test-Path $nginxTemplatePath)) {
        throw 'Missing nginx.conf.template in the repo root.'
    }
}

function Ensure-DockerNetwork {
    param(
        [pscustomobject]$Profile,
        [string]$NetworkName,
        [string]$WorkingDirectory
    )

    if ($Profile.IsLocal) {
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
        Invoke-RemoteShell -Profile $Profile -Command $createCommand -WorkingDirectory $WorkingDirectory
    }
    catch {
        throw "Failed to ensure Docker network '$NetworkName': $($_.Exception.Message)"
    }
}

function Invoke-ComposeStack {
    param(
        [pscustomobject]$Profile,
        [string]$WorkingDirectory,
        [bool]$RemoveVolumes,
        [bool]$Build,
        [string]$NetworkName,
        [string]$ApiHostName,
        [string]$ApiPortNumber
    )

    $downFlag = if ($RemoveVolumes) { ' -v' } else { '' }
    $composeDown = "docker compose -f $Script:ComposeFile down$downFlag"
    $buildFlag = if ($Build) { ' --build' } else { '' }
    $composeUp = "docker compose -f $Script:ComposeFile up -d$buildFlag"

    if ($Profile.IsLocal) {
        Push-Location $WorkingDirectory
        try {
            Set-ComposeEnvironment -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber -PublishHostPorts:$Profile.IsLocal
            Invoke-Expression $composeDown | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Compose down skipped or partial (stack may not exist yet).' -ForegroundColor DarkYellow
            }
            Invoke-Expression $composeUp | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
        }
        finally {
            Pop-Location
        }
        return
    }

    try {
        Invoke-RemoteShell -Profile $Profile -Command $composeDown -WorkingDirectory $WorkingDirectory
    }
    catch {
        Write-Host "Compose down skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $envPrefix = Get-RemoteComposeEnvironmentPrefix -NetworkName $NetworkName -ApiHostName $ApiHostName -ApiPortNumber $ApiPortNumber -PublishHostPorts:$Profile.IsLocal
    Invoke-RemoteShell -Profile $Profile -Command "${envPrefix}$composeUp" -WorkingDirectory $WorkingDirectory
}

if ($Help -or $SshString -match '^(-h|-help|--help|-\?|/\?)$') {
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

$profile = Resolve-SshProfile -ConnectionString $sshStringValue
$workDir = if ($profile.IsLocal) { $ProjectRoot } else { Get-RemoteWorkDir -ProjectRoot $ProjectRoot }
$imageTags = Get-StackImageTags -ProjectRoot $ProjectRoot
$stackManifest = Get-StackManifest -ProjectRoot $ProjectRoot
$stackName = if ($stackManifest -and $stackManifest.stackName) { [string]$stackManifest.stackName } else { 'translator' }

$targetLabel = if ($profile.IsLocal) { 'localhost' } elseif ($profile.Mode -eq 'ssh-alias') { "ssh $($profile.SshAlias)" } else { "$($profile.Username)@$($profile.Server)" }
$volumeAction = if ($removeVolumes) { 'removing volumes' } else { 'keeping volumes' }
$totalSteps = if ($profile.IsLocal) { 4 } else { 7 }

try {
    $deployMode = if ($profile.IsLocal) { 'local Docker' } else { 'local build + image transfer' }
    Write-Host ("Target: {0} ({1}) | network: {2} | api: {3}:{4} | images: {5}, {6} | {7}" -f `
        $targetLabel, $deployMode, $networkValue, $apiHostValue, $apiPortValue, `
        $imageTags.ApiImageTag, $imageTags.WebImageTag, $volumeAction) -ForegroundColor Cyan

    Write-RunStep -Step 1 -Total $totalSteps -Message 'Checking Docker files'
    Test-DockerComposeFile -ProjectRoot $ProjectRoot
    Test-DockerCliAvailable -Profile $profile

    Write-RunStep -Step 2 -Total $totalSteps -Message 'Building API and web images'
    Build-LocalDockerImages -ProjectRoot $ProjectRoot

    if ($profile.IsLocal) {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Profile $profile -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Profile $profile -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -Build:$false -NetworkName $networkValue -ApiHostName $apiHostValue -ApiPortNumber $apiPortValue
    }
    else {
        Write-RunStep -Step 3 -Total $totalSteps -Message "Syncing compose files to $targetLabel"
        Sync-DeployFilesToRemote -Profile $profile -LocalRoot $ProjectRoot -RemotePath $workDir

        Write-RunStep -Step 4 -Total $totalSteps -Message 'Transferring images to remote host'
        Transfer-DockerImagesToRemote -Profile $profile -ImageTags @($imageTags.ApiImageTag, $imageTags.WebImageTag) -RemotePath $workDir -StackName $stackName

        Write-RunStep -Step 5 -Total $totalSteps -Message 'Checking remote Docker'
        Test-DockerCliAvailable -Profile $profile

        Write-RunStep -Step 6 -Total $totalSteps -Message "Ensuring Docker network '$networkValue'"
        Ensure-DockerNetwork -Profile $profile -NetworkName $networkValue -WorkingDirectory $workDir

        Write-RunStep -Step 7 -Total $totalSteps -Message $(if ($removeVolumes) { 'Recreating stack (volumes removed)' } else { 'Recreating stack (keeping volumes)' })
        Invoke-ComposeStack -Profile $profile -WorkingDirectory $workDir -RemoveVolumes:$removeVolumes -Build:$false -NetworkName $networkValue -ApiHostName $apiHostValue -ApiPortNumber $apiPortValue
    }

    Write-Progress -Activity 'translator Docker run' -Completed -Status 'Done'
    Write-Host ''

    if ($profile.IsLocal) {
        Write-Host 'Stack is running on localhost.' -ForegroundColor Green
        Write-Host '  Web UI: http://localhost:8082' -ForegroundColor Green
        Write-Host '  API:    http://localhost:8080' -ForegroundColor Green
    }
    else {
        Write-Host "Stack is running on remote host at $workDir (network: $networkValue, api: ${apiHostValue}:${apiPortValue})." -ForegroundColor Green
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
