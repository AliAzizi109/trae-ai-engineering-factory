<#
.SYNOPSIS
Safely compares or syncs the tracked factory baseline into an adopter repository.

.DESCRIPTION
Reads the authoritative manifest from `.trae/factory/config/baseline-files.manifest.json`
and builds a non-destructive sync plan for a target repository. The script runs in
check-only mode by default, never deletes files, and skips project-specific files such
as `README.md` and `.trae/current-project-state.md` unless `-IncludeProjectSpecific`
is explicitly provided.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetProjectRoot,

    [Parameter()]
    [switch]$Apply,

    [Parameter()]
    [switch]$IncludeProjectSpecific,

    [Parameter()]
    [switch]$FailOnDifferences
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Resolves the baseline repository root from the script location.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the baseline project root from script path: $PSScriptRoot"
    }

    return [System.IO.Path]::GetFullPath($projectRoot)
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
    Returns whether a manifest path is a safe repository-relative file path.
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

        if (-not $entry.sync) {
            throw "Baseline manifest entry is missing sync metadata for path: '$($entry.path)'"
        }
    }

    return $manifest
}

function Resolve-TargetProjectRoot {
    <#
    .SYNOPSIS
    Resolves and validates the adopter repository root.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Target project root does not exist or is not a directory: $Path"
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-EffectiveSyncMode {
    <#
    .SYNOPSIS
    Returns the effective sync mode for a manifest entry.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Entry,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific
    )

    $defaultMode = [string]$Entry.sync.default_mode
    if ([string]::IsNullOrWhiteSpace($defaultMode)) {
        throw "Manifest entry '$($Entry.path)' is missing sync.default_mode."
    }

    if ($AllowProjectSpecific -and -not [string]::IsNullOrWhiteSpace([string]$Entry.sync.override_mode)) {
        return [string]$Entry.sync.override_mode
    }

    return $defaultMode
}

function Test-FileContentMatch {
    <#
    .SYNOPSIS
    Returns whether two files have identical content.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Source file not found: $SourcePath"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        return $false
    }

    $sourceHash = Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256
    $destinationHash = Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256

    return $sourceHash.Hash -eq $destinationHash.Hash
}

function New-SyncPlanItem {
    <#
    .SYNOPSIS
    Creates a normalized sync plan item.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [bool]$TargetExists,

        [Parameter(Mandatory = $true)]
        [bool]$NeedsUpdate
    )

    return [pscustomobject]@{
        RelativePath = $RelativePath
        Category = $Category
        Mode = $Mode
        Status = $Status
        Reason = $Reason
        SourcePath = $SourcePath
        TargetPath = $TargetPath
        TargetExists = $TargetExists
        NeedsUpdate = $NeedsUpdate
    }
}

function Get-SyncPlan {
    <#
    .SYNOPSIS
    Builds a safe, non-destructive sync plan from the manifest.
    #>
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineRoot,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific
    )

    $manifest = Get-BaselineManifest -ProjectRoot $BaselineRoot
    $plan = New-Object System.Collections.Generic.List[psobject]

    foreach ($entry in $manifest.files) {
        $relativePath = [string]$entry.path
        $sourcePath = Join-Path -Path $BaselineRoot -ChildPath $relativePath
        $targetPath = Join-Path -Path $TargetRoot -ChildPath $relativePath
        $mode = Get-EffectiveSyncMode -Entry $entry -AllowProjectSpecific $AllowProjectSpecific
        $category = [string]$entry.sync.category
        $reason = [string]$entry.sync.reason
        $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Manifest entry source file is missing in baseline: $sourcePath"
        }

        switch ($mode) {
            'skip' {
                $status = if ($targetExists) { 'skipped_existing' } else { 'skipped_missing' }
                $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status $status -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $targetExists -NeedsUpdate $false))
                continue
            }
            'copy_if_different' {
                if (-not $targetExists) {
                    $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status 'missing' -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $false -NeedsUpdate $true))
                    continue
                }

                $isMatch = Test-FileContentMatch -SourcePath $sourcePath -DestinationPath $targetPath
                if ($isMatch) {
                    $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status 'in_sync' -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $true -NeedsUpdate $false))
                }
                else {
                    $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status 'different' -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $true -NeedsUpdate $true))
                }

                continue
            }
            default {
                throw "Unsupported sync mode '$mode' for manifest entry: $relativePath"
            }
        }
    }

    return $plan.ToArray()
}

function Invoke-SyncPlan {
    <#
    .SYNOPSIS
    Applies the non-destructive portion of the sync plan.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Plan
    )

    foreach ($item in $Plan) {
        if (-not $item.NeedsUpdate) {
            continue
        }

        if ($item.Mode -ne 'copy_if_different') {
            continue
        }

        $targetDirectory = Split-Path -Parent $item.TargetPath
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }

        Copy-Item -LiteralPath $item.SourcePath -Destination $item.TargetPath -Force
    }
}

function Write-SyncPlan {
    <#
    .SYNOPSIS
    Prints a concise sync summary and itemized plan.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$IsApply
    )

    $missingCount = @($Plan | Where-Object { $_.Status -eq 'missing' }).Count
    $differentCount = @($Plan | Where-Object { $_.Status -eq 'different' }).Count
    $skippedCount = @($Plan | Where-Object { $_.Mode -eq 'skip' }).Count
    $inSyncCount = @($Plan | Where-Object { $_.Status -eq 'in_sync' }).Count

    Write-Host "Baseline sync target: $TargetRoot"
    Write-Host ("Mode: {0}" -f $(if ($IsApply) { 'apply' } else { 'check-only' }))
    Write-Host "Summary: in-sync=$inSyncCount, missing=$missingCount, different=$differentCount, skipped=$skippedCount"

    foreach ($item in $Plan) {
        Write-Host ("[{0}] {1} ({2})" -f $item.Status.ToUpperInvariant(), $item.RelativePath, $item.Reason)
    }
}

function Main {
    <#
    .SYNOPSIS
    Builds and optionally applies the safe baseline sync plan.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldFailOnDifferences
    )

    $baselineRoot = Get-ProjectRoot
    $targetRoot = Resolve-TargetProjectRoot -Path $RequestedTargetRoot
    $plan = Get-SyncPlan -BaselineRoot $baselineRoot -TargetRoot $targetRoot -AllowProjectSpecific $AllowProjectSpecific

    Write-SyncPlan -Plan $plan -TargetRoot $targetRoot -IsApply $ShouldApply

    if ($ShouldApply) {
        Invoke-SyncPlan -Plan $plan
        Write-Host 'Baseline sync apply completed successfully.'
        return
    }

    $hasDifferences = @($plan | Where-Object { $_.NeedsUpdate }).Count -gt 0
    if ($hasDifferences) {
        Write-Warning 'Differences were found. Re-run with -Apply to copy safe baseline-managed files.'

        if ($ShouldFailOnDifferences) {
            throw 'Baseline sync check detected differences.'
        }

        return
    }

    Write-Host 'Baseline sync check passed. No safe sync changes are pending.'
}

try {
    Main -RequestedTargetRoot $TargetProjectRoot -ShouldApply $Apply.IsPresent -AllowProjectSpecific $IncludeProjectSpecific.IsPresent -ShouldFailOnDifferences $FailOnDifferences.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
