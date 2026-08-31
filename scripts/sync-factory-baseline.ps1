<#
.SYNOPSIS
Safely compares or syncs the tracked factory baseline into an adopter repository.

.DESCRIPTION
Reads the authoritative manifest from `.trae/factory/config/baseline-files.manifest.json`
and builds a non-destructive sync plan for a target repository. The script runs in
check-only mode by default, never deletes files, and supports a seed-missing-only
mode for project-specific files such as `README.md` and `.trae/current-project-state.md`.
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
    [switch]$SeedProjectSpecificIfMissing,

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

    $manifestPath = Join-Path -Path $ProjectRoot -ChildPath '.trae\factory\config\baseline-files.manifest.json'
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
    Resolves the requested adopter repository root and records whether it already exists.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)

    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw "Target project root exists but is not a directory: $fullPath"
        }

        return [pscustomobject]@{
            Path = $fullPath
            Exists = $true
            ParentPath = Split-Path -Parent $fullPath
        }
    }

    return [pscustomobject]@{
        Path = $fullPath
        Exists = $false
        ParentPath = Split-Path -Parent $fullPath
    }
}

function Get-ManifestDeclaredMode {
    <#
    .SYNOPSIS
    Returns the manifest-declared sync mode for an entry.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Entry,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific
    )

    $defaultModeProperty = $Entry.sync.PSObject.Properties['default_mode']
    $defaultMode = if ($null -ne $defaultModeProperty) { [string]$defaultModeProperty.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($defaultMode)) {
        throw "Manifest entry '$($Entry.path)' is missing sync.default_mode."
    }

    $overrideModeProperty = $Entry.sync.PSObject.Properties['override_mode']
    $overrideMode = if ($null -ne $overrideModeProperty) { [string]$overrideModeProperty.Value } else { '' }

    if ($AllowProjectSpecific -and -not [string]::IsNullOrWhiteSpace($overrideMode)) {
        return $overrideMode
    }

    return $defaultMode
}

function Get-EffectiveSyncMode {
    <#
    .SYNOPSIS
    Returns the effective sync mode for a manifest entry in the current run.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Entry,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific,

        [Parameter(Mandatory = $true)]
        [bool]$SeedMissingProjectSpecific
    )

    $declaredMode = Get-ManifestDeclaredMode -Entry $Entry -AllowProjectSpecific $AllowProjectSpecific
    $category = [string]$Entry.sync.category

    if ($SeedMissingProjectSpecific -and $category -eq 'project_specific' -and -not $AllowProjectSpecific) {
        return 'seed_if_missing'
    }

    return $declaredMode
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
        [bool]$AllowProjectSpecific,

        [Parameter(Mandatory = $true)]
        [bool]$SeedMissingProjectSpecific
    )

    $manifest = Get-BaselineManifest -ProjectRoot $BaselineRoot
    $plan = New-Object System.Collections.Generic.List[psobject]

    foreach ($entry in $manifest.files) {
        $relativePath = [string]$entry.path
        $sourcePath = Join-Path -Path $BaselineRoot -ChildPath $relativePath
        $targetPath = Join-Path -Path $TargetRoot -ChildPath $relativePath
        $mode = Get-EffectiveSyncMode -Entry $entry -AllowProjectSpecific $AllowProjectSpecific -SeedMissingProjectSpecific $SeedMissingProjectSpecific
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
            'seed_if_missing' {
                if ($targetExists) {
                    $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status 'skipped_existing' -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $true -NeedsUpdate $false))
                }
                else {
                    $plan.Add((New-SyncPlanItem -RelativePath $relativePath -Category $category -Mode $mode -Status 'missing_seed' -Reason $reason -SourcePath $sourcePath -TargetPath $targetPath -TargetExists $false -NeedsUpdate $true))
                }

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

function Get-SyncSummary {
    <#
    .SYNOPSIS
    Builds a compact summary from a sync plan.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Plan
    )

    $pendingItems = @($Plan | Where-Object { $_.NeedsUpdate })

    return [pscustomobject]@{
        InSyncCount = @($Plan | Where-Object { $_.Status -eq 'in_sync' }).Count
        MissingCount = @($Plan | Where-Object { $_.Status -eq 'missing' }).Count
        MissingSeedCount = @($Plan | Where-Object { $_.Status -eq 'missing_seed' }).Count
        DifferentCount = @($Plan | Where-Object { $_.Status -eq 'different' }).Count
        SkippedExistingCount = @($Plan | Where-Object { $_.Status -eq 'skipped_existing' }).Count
        SkippedMissingCount = @($Plan | Where-Object { $_.Status -eq 'skipped_missing' }).Count
        PendingChangeCount = $pendingItems.Count
        BaselineFilesToEstablishCount = @($pendingItems | Where-Object { $_.Status -eq 'missing' }).Count
        ProjectSpecificFilesToSeedCount = @($pendingItems | Where-Object { $_.Status -eq 'missing_seed' }).Count
        FilesToUpdateCount = @($pendingItems | Where-Object { $_.Status -eq 'different' }).Count
    }
}

function Invoke-SyncPlan {
    <#
    .SYNOPSIS
    Applies the non-destructive portion of the sync plan.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Plan,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$CreateTargetRoot
    )

    $targetRootCreated = $false

    if ($CreateTargetRoot -and -not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
        $targetRootCreated = $true
    }

    foreach ($item in $Plan) {
        if (-not $item.NeedsUpdate) {
            continue
        }

        if ($item.Mode -notin @('copy_if_different', 'seed_if_missing')) {
            continue
        }

        $targetDirectory = Split-Path -Parent $item.TargetPath
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }

        Copy-Item -LiteralPath $item.SourcePath -Destination $item.TargetPath -Force
    }

    return [pscustomobject]@{
        TargetRootCreated = $targetRootCreated
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
        [pscustomobject]$Summary,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$TargetInfo,

        [Parameter(Mandatory = $true)]
        [bool]$IsApply
    )

    $modeLabel = if ($IsApply) { 'apply' } else { 'check-only' }
    $rootStatus = if ($TargetInfo.Exists) { 'existing' } else { 'will_create_on_apply' }

    Write-Host "Baseline sync target: $($TargetInfo.Path)"
    Write-Host "Mode: $modeLabel"
    Write-Host "Target root status: $rootStatus"
    Write-Host ("Summary: in-sync={0}, establish={1}, seed-project-specific={2}, update={3}, skipped-existing={4}, skipped-missing={5}" -f `
        $Summary.InSyncCount,
        $Summary.BaselineFilesToEstablishCount,
        $Summary.ProjectSpecificFilesToSeedCount,
        $Summary.FilesToUpdateCount,
        $Summary.SkippedExistingCount,
        $Summary.SkippedMissingCount)

    foreach ($item in $Plan) {
        Write-Host ("[{0}] {1} ({2})" -f $item.Status.ToUpperInvariant(), $item.RelativePath, $item.Reason)
    }
}

function Main {
    <#
    .SYNOPSIS
    Builds and optionally applies the safe baseline sync plan.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply,

        [Parameter(Mandatory = $true)]
        [bool]$AllowProjectSpecific,

        [Parameter(Mandatory = $true)]
        [bool]$SeedMissingProjectSpecific,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldFailOnDifferences
    )

    if ($AllowProjectSpecific -and $SeedMissingProjectSpecific) {
        throw 'Use either -IncludeProjectSpecific or -SeedProjectSpecificIfMissing, not both.'
    }

    $baselineRoot = Get-ProjectRoot
    $targetInfo = Resolve-TargetProjectRoot -Path $RequestedTargetRoot
    $plan = Get-SyncPlan -BaselineRoot $baselineRoot -TargetRoot $targetInfo.Path -AllowProjectSpecific $AllowProjectSpecific -SeedMissingProjectSpecific $SeedMissingProjectSpecific
    $summary = Get-SyncSummary -Plan $plan

    Write-SyncPlan -Plan $plan -Summary $summary -TargetInfo $targetInfo -IsApply $ShouldApply

    $applyResult = [pscustomobject]@{
        TargetRootCreated = $false
    }

    if ($ShouldApply) {
        $applyResult = Invoke-SyncPlan -Plan $plan -TargetRoot $targetInfo.Path -CreateTargetRoot (-not $targetInfo.Exists)
        Write-Host 'Baseline sync apply completed successfully.'
    }
    else {
        $hasDifferences = $summary.PendingChangeCount -gt 0
        if ($hasDifferences) {
            Write-Warning 'Differences were found. Re-run with -Apply to copy safe baseline-managed files.'

            if ($ShouldFailOnDifferences) {
                throw 'Baseline sync check detected differences.'
            }
        }
        else {
            Write-Host 'Baseline sync check passed. No safe sync changes are pending.'
        }
    }

    return [pscustomobject]@{
        TargetRoot = $targetInfo.Path
        Mode = if ($ShouldApply) { 'apply' } else { 'check-only' }
        TargetRootExistedBeforeRun = $targetInfo.Exists
        TargetRootCreated = $applyResult.TargetRootCreated
        Plan = $plan
        Summary = $summary
    }
}

try {
    Main -RequestedTargetRoot $TargetProjectRoot -ShouldApply $Apply.IsPresent -AllowProjectSpecific $IncludeProjectSpecific.IsPresent -SeedMissingProjectSpecific $SeedProjectSpecificIfMissing.IsPresent -ShouldFailOnDifferences $FailOnDifferences.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
