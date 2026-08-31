<#
.SYNOPSIS
Bootstraps the local project-level MCP filesystem server dependencies.

.DESCRIPTION
Uses the tracked package.json and package-lock.json under .trae-local to
install the required project-fs MCP dependencies deterministically on a new
machine. Run this script from the repository as needed.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Returns the repository root based on this script location.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return $projectRoot
}

function Get-NodeToolPreflight {
    <#
    .SYNOPSIS
    Resolves the node/npm commands required for project-fs bootstrap.
    #>
    [OutputType([pscustomobject])]
    param()

    $nodeCommand = Get-Command -Name 'node' -ErrorAction SilentlyContinue
    $npmCommand = Get-Command -Name 'npm.cmd' -ErrorAction SilentlyContinue
    $missingPrerequisites = New-Object System.Collections.Generic.List[string]

    if ($null -eq $nodeCommand -or [string]::IsNullOrWhiteSpace([string]$nodeCommand.Source)) {
        $missingPrerequisites.Add('node')
    }

    if ($null -eq $npmCommand -or [string]::IsNullOrWhiteSpace([string]$npmCommand.Source)) {
        $missingPrerequisites.Add('npm.cmd')
    }

    return [pscustomobject]@{
        Ready = $missingPrerequisites.Count -eq 0
        NodeCommandPath = if ($null -ne $nodeCommand) { [string]$nodeCommand.Source } else { $null }
        NpmCommandPath = if ($null -ne $npmCommand) { [string]$npmCommand.Source } else { $null }
        MissingPrerequisites = $missingPrerequisites.ToArray()
        Remediation = 'Install Node.js so that both node and npm.cmd are available on PATH, then re-run scripts/bootstrap-project-fs.ps1.'
    }
}

function Assert-TrackedProjectFsInputs {
    <#
    .SYNOPSIS
    Ensures the tracked project-fs bootstrap inputs exist before installation.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $installDirectory = Join-Path -Path $ProjectRoot -ChildPath '.trae-local\mcp\project-fs'
    $packageJsonPath = Join-Path -Path $installDirectory -ChildPath 'package.json'
    $packageLockPath = Join-Path -Path $installDirectory -ChildPath 'package-lock.json'

    if (-not (Test-Path -LiteralPath $installDirectory -PathType Container)) {
        throw "Missing tracked project-fs directory at: $installDirectory"
    }

    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        throw "Missing tracked package.json at: $packageJsonPath"
    }

    if (-not (Test-Path -LiteralPath $packageLockPath -PathType Leaf)) {
        throw "Missing tracked package-lock.json at: $packageLockPath"
    }

    return [pscustomobject]@{
        InstallDirectory = $installDirectory
        PackageJsonPath = $packageJsonPath
        PackageLockPath = $packageLockPath
    }
}

function Install-ProjectFsDependencies {
    <#
    .SYNOPSIS
    Installs the local npm dependencies inside the project-fs directory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory,

        [Parameter(Mandatory = $true)]
        [string]$NpmCommandPath
    )

    $installArgs = @('ci', '--no-audit', '--no-fund')
    $startProcessParams = @{
        FilePath = $npmCommandPath
        ArgumentList = $installArgs
        WorkingDirectory = $InstallDirectory
        NoNewWindow = $true
        Wait = $true
        PassThru = $true
    }

    $process = Start-Process @startProcessParams

    if ($process.ExitCode -ne 0) {
        throw "npm ci failed with exit code $($process.ExitCode)."
    }
}

function Main {
    <#
    .SYNOPSIS
    Prepares the local project-fs MCP installation.
    #>
    [OutputType([pscustomobject])]
    param()

    $projectRoot = Get-ProjectRoot
    $trackedInputs = Assert-TrackedProjectFsInputs -ProjectRoot $projectRoot
    $preflight = Get-NodeToolPreflight

    if (-not $preflight.Ready) {
        $missingList = $preflight.MissingPrerequisites -join ', '
        Write-Warning "Project-fs bootstrap deferred. Missing prerequisites on PATH: $missingList"
        Write-Host "Remediation: $($preflight.Remediation)"
        Write-Host "Deferred script: scripts/bootstrap-project-fs.ps1"
        return [pscustomobject]@{
            Status = 'deferred'
            InstallDirectory = $trackedInputs.InstallDirectory
            MissingPrerequisites = $preflight.MissingPrerequisites
            Remediation = $preflight.Remediation
        }
    }

    Install-ProjectFsDependencies -InstallDirectory $trackedInputs.InstallDirectory -NpmCommandPath $preflight.NpmCommandPath

    Write-Host "Local project-fs MCP dependencies are ready in: $($trackedInputs.InstallDirectory)"
    return [pscustomobject]@{
        Status = 'ready'
        InstallDirectory = $trackedInputs.InstallDirectory
        NpmCommandPath = $preflight.NpmCommandPath
        NodeCommandPath = $preflight.NodeCommandPath
    }
}

try {
    Main
}
catch {
    Write-Error $_
    exit 1
}
