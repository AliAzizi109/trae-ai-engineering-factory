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

function Get-NpmCommandPath {
    <#
    .SYNOPSIS
    Resolves npm.cmd to avoid PowerShell execution policy issues with npm.ps1.
    #>
    [OutputType([string])]
    param()

    $npmCommand = Get-Command -Name 'npm.cmd' -ErrorAction Stop
    if (-not $npmCommand.Source) {
        throw 'npm.cmd was found, but its executable path could not be resolved.'
    }

    return $npmCommand.Source
}

function Install-ProjectFsDependencies {
    <#
    .SYNOPSIS
    Installs the local npm dependencies inside the project-fs directory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallDirectory
    )

    $npmCommandPath = Get-NpmCommandPath
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
    [OutputType([void])]
    param()

    $projectRoot = Get-ProjectRoot
    $installDirectory = Join-Path -Path $projectRoot -ChildPath '.trae-local\mcp\project-fs'
    $packageJsonPath = Join-Path -Path $installDirectory -ChildPath 'package.json'
    $packageLockPath = Join-Path -Path $installDirectory -ChildPath 'package-lock.json'

    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null

    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        throw "Missing tracked package.json at: $packageJsonPath"
    }

    if (-not (Test-Path -LiteralPath $packageLockPath -PathType Leaf)) {
        throw "Missing tracked package-lock.json at: $packageLockPath"
    }

    Install-ProjectFsDependencies -InstallDirectory $installDirectory

    Write-Host "Local project-fs MCP dependencies are ready in: $installDirectory"
}

Main
