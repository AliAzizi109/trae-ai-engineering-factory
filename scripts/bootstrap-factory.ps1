<#
.SYNOPSIS
Validates the factory baseline and optionally bootstraps project-fs.

.DESCRIPTION
Checks that the tracked baseline files required for a new machine or cloned
project are present. When validation succeeds, the script either exits after a
success message in check-only mode or runs the project-fs bootstrap script.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$CheckOnly
)

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

function Get-BaselineManifestPath {
    <#
    .SYNOPSIS
    Returns the authoritative baseline manifest path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $manifestPath = Join-Path -Path $ProjectRoot -ChildPath '.trae\\factory\\config\\baseline-files.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Baseline manifest not found at: $manifestPath"
    }

    return $manifestPath
}

function Test-RelativeManifestPath {
    <#
    .SYNOPSIS
    Returns whether a manifest entry path is a safe repository-relative file path.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return $false
    }

    if ($RelativePath.Contains('..')) {
        return $false
    }

    return $true
}

function Get-BaselineManifest {
    <#
    .SYNOPSIS
    Loads and validates the authoritative baseline manifest.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $manifestPath = Get-BaselineManifestPath -ProjectRoot $ProjectRoot

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Unable to parse baseline manifest at '$manifestPath'. $($_.Exception.Message)"
    }

    if (-not $manifest.files) {
        throw "Baseline manifest does not define any files: $manifestPath"
    }

    $seenPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $manifest.files) {
        if (-not (Test-RelativeManifestPath -RelativePath $entry.path)) {
            throw "Baseline manifest contains an invalid relative file path: '$($entry.path)'"
        }

        if (-not $seenPaths.Add([string]$entry.path)) {
            throw "Baseline manifest contains a duplicate file path: '$($entry.path)'"
        }
    }

    return $manifest
}

function Get-BaselineRelativePaths {
    <#
    .SYNOPSIS
    Returns the required baseline files for the factory bootstrap from the manifest.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $manifest = Get-BaselineManifest -ProjectRoot $ProjectRoot
    $relativePaths = New-Object System.Collections.Generic.List[string]

    foreach ($entry in $manifest.files) {
        if ($entry.bootstrap_required -ne $false) {
            $relativePaths.Add([string]$entry.path)
        }
    }

    return $relativePaths.ToArray()
}

function Get-MissingBaselineFiles {
    <#
    .SYNOPSIS
    Returns any missing required baseline files.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $missingFiles = New-Object System.Collections.Generic.List[string]

    foreach ($relativePath in Get-BaselineRelativePaths -ProjectRoot $ProjectRoot) {
        $fullPath = Join-Path -Path $ProjectRoot -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missingFiles.Add($relativePath)
        }
    }

    return $missingFiles.ToArray()
}

function Assert-BaselineFiles {
    <#
    .SYNOPSIS
    Ensures all required baseline files exist before bootstrap continues.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $missingFiles = @(Get-MissingBaselineFiles -ProjectRoot $ProjectRoot)
    if ($missingFiles.Count -gt 0) {
        $missingList = ($missingFiles | ForEach-Object { "- $_" }) -join [Environment]::NewLine
        throw "Factory baseline validation failed. Missing files:$([Environment]::NewLine)$missingList"
    }
}

function Invoke-ProjectFsBootstrap {
    <#
    .SYNOPSIS
    Runs the tracked project-fs bootstrap script.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $bootstrapScriptPath = Join-Path -Path $ProjectRoot -ChildPath 'scripts\bootstrap-project-fs.ps1'
    if (-not (Test-Path -LiteralPath $bootstrapScriptPath -PathType Leaf)) {
        throw "Bootstrap script not found at: $bootstrapScriptPath"
    }

    & $bootstrapScriptPath
}

function Main {
    <#
    .SYNOPSIS
    Validates the baseline and optionally prepares the local project-fs setup.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $projectRoot = Get-ProjectRoot
    Assert-BaselineFiles -ProjectRoot $projectRoot

    if ($IsCheckOnly) {
        $manifestPath = Get-BaselineManifestPath -ProjectRoot $projectRoot
        Write-Host "Factory baseline check passed. All required manifest files are present: $manifestPath"
        return
    }

    Invoke-ProjectFsBootstrap -ProjectRoot $projectRoot
    Write-Host 'Factory bootstrap completed successfully.'
    Write-Host 'Next steps:'
    Write-Host '1. Review git status.'
    Write-Host '2. Start a tracked task quickly with scripts/start-factory-task.ps1, or use scripts/new-factory-task.ps1 directly.'
    Write-Host '3. Use scripts/get-factory-operator-status.ps1 for a repo-level or task-level dashboard.'
    Write-Host '4. Use scripts/select-factory-model.ps1 before role execution when you need deterministic fallback routing.'
    Write-Host '5. Resume or checkpoint that task with scripts/update-factory-task.ps1 as work progresses.'
    Write-Host '6. Inspect normalized task details with scripts/get-factory-task-summary.ps1 when needed.'
    Write-Host '7. Use scripts/sync-factory-baseline.ps1 in check-only mode first when syncing this baseline into an adopter.'
    Write-Host '8. Commit/push the baseline or publish the template when ready.'
}

try {
    Main -IsCheckOnly $CheckOnly.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
