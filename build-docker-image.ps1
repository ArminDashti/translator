<#
.SYNOPSIS
    Build translator Docker images (API, web, or both).

.DESCRIPTION
    Uses the repo-root Dockerfile (multi-target) and docker-compose.yml.
    Image tags default to values in .docker/stack.manifest.json.

.PARAMETER BuildTarget
    Which image(s) to build: api, web, or all. Default: all.

.PARAMETER NoCache
    Rebuild without using the Docker cache. Default: no.

.PARAMETER ComposeFile
    Compose file path relative to the repo root. Default: docker-compose.yml.

.EXAMPLE
    .\build-docker-image.ps1

.EXAMPLE
    .\build-docker-image.ps1 --target=api

.EXAMPLE
    .\build-docker-image.ps1 --target=web --no-cache=yes
#>
[CmdletBinding()]
param(
    [Alias('target')]
    [string]$BuildTarget = 'all',
    [Alias('no-cache')]
    [string]$NoCache = 'no',
    [Alias('compose-file')]
    [string]$ComposeFile = 'docker-compose.yml',
    [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-BuildDockerImageHelp {
    Write-Host @'
translator Docker build - build API and/or web images

Usage:
  .\build-docker-image.ps1 [--target=<api|web|all>] [--no-cache=<no|yes>] [--compose-file=<path>]

Arguments:
  --target=<api|web|all>      Image(s) to build (default: all)
  --no-cache=<no|yes>         Rebuild without Docker cache (default: no)
  --compose-file=<path>       Compose file in repo root (default: docker-compose.yml)

Examples:
  .\build-docker-image.ps1
  .\build-docker-image.ps1 --target=api
  .\build-docker-image.ps1 --target=web --no-cache=yes

Requires Dockerfile and docker-compose.yml in the repo root.
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
        elseif ($argument -match '^(-help|-\?|/\?)$') {
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

function Write-BuildStep {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Message
    )

    $percent = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity 'translator Docker build' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $Step, $Total, $Message) -ForegroundColor Yellow
}

function Test-DockerCliAvailable {
    & docker version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker CLI is not available or not running.'
    }
}

function Test-BuildFiles {
    param(
        [string]$ProjectRoot,
        [string]$ComposeFileName
    )

    $composePath = Join-Path $ProjectRoot $ComposeFileName
    if (-not (Test-Path $composePath)) {
        throw "Missing compose file: $ComposeFileName"
    }

    $dockerfilePath = Join-Path $ProjectRoot 'Dockerfile'
    if (-not (Test-Path $dockerfilePath)) {
        throw 'Missing Dockerfile in the repo root.'
    }

    return $composePath
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

function Resolve-BuildServices {
    param([string]$TargetValue)

    switch ($TargetValue.ToLowerInvariant()) {
        'api' { return @('api') }
        'web' { return @('web') }
        'all' { return @('api', 'web') }
        default { throw "Invalid --target value '$TargetValue'. Use api, web, or all." }
    }
}

function Invoke-DockerImageBuild {
    param(
        [string]$ProjectRoot,
        [string]$ComposeFileName,
        [string[]]$Services,
        [bool]$UseNoCache
    )

    Push-Location $ProjectRoot
    try {
        $buildArgs = @('compose', '-f', $ComposeFileName, 'build')
        if ($UseNoCache) {
            $buildArgs += '--no-cache'
        }
        $buildArgs += $Services

        & docker @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose build failed (exit $LASTEXITCODE)"
        }
    }
    finally {
        Pop-Location
    }
}

if ($Help) {
    Show-BuildDockerImageHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$cliArgs = Merge-CliArguments -BoundParameters $PSBoundParameters -RemainingArguments $RemainingArguments
if ($cliArgs['help']) {
    Show-BuildDockerImageHelp
    Get-Help $PSCommandPath -Full
    exit 0
}

$targetValue = if ($cliArgs['target']) { [string]$cliArgs['target'] } else { [string]$BuildTarget }
$targetValue = Normalize-CliParameterValue -Name 'target' -Value $targetValue
$noCacheValue = if ($cliArgs['no_cache']) { [string]$cliArgs['no_cache'] } else { [string]$NoCache }
$noCacheValue = Normalize-CliParameterValue -Name 'no_cache' -Value $noCacheValue
$composeFileValue = if ($cliArgs['compose_file']) { [string]$cliArgs['compose_file'] } else { [string]$ComposeFile }
$composeFileValue = Normalize-CliParameterValue -Name 'compose_file' -Value $composeFileValue

$useNoCache = Test-Truthy -Value $noCacheValue
$services = Resolve-BuildServices -TargetValue $targetValue
$ProjectRoot = $PSScriptRoot
$imageTags = Get-StackImageTags -ProjectRoot $ProjectRoot
$totalSteps = 3

try {
    $serviceLabel = ($services -join ', ')
    $cacheLabel = if ($useNoCache) { 'no cache' } else { 'with cache' }
    Write-Host ("Building: {0} ({1}) | compose: {2}" -f $serviceLabel, $cacheLabel, $composeFileValue) -ForegroundColor Cyan

    Write-BuildStep -Step 1 -Total $totalSteps -Message 'Checking Docker and build files'
    Test-DockerCliAvailable
    $null = Test-BuildFiles -ProjectRoot $ProjectRoot -ComposeFileName $composeFileValue

    Write-BuildStep -Step 2 -Total $totalSteps -Message "Building image(s): $serviceLabel"
    Invoke-DockerImageBuild -ProjectRoot $ProjectRoot -ComposeFileName $composeFileValue -Services $services -UseNoCache:$useNoCache

    Write-BuildStep -Step 3 -Total $totalSteps -Message 'Build complete'
    Write-Progress -Activity 'translator Docker build' -Completed -Status 'Done'
    Write-Host ''

    if ($services -contains 'api') {
        Write-Host "  API image: $($imageTags.ApiImageTag)" -ForegroundColor Green
    }
    if ($services -contains 'web') {
        Write-Host "  Web image: $($imageTags.WebImageTag)" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host 'Run the stack with .\run-on-docker.ps1' -ForegroundColor Cyan
}
catch {
    Write-Progress -Activity 'translator Docker build' -Completed -Status 'Failed'
    Write-Host ''
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Show-BuildDockerImageHelp
    exit 1
}
