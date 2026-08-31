<#
.SYNOPSIS
Runs the canonical factory adoption flow for new-project startup or existing-project adoption.

.DESCRIPTION
From the baseline repository, this script provides two operator paths on top of
the same adoption pipeline:
- New-project startup for a missing or empty target directory
- Existing-project adoption for preview-first or in-place adoption

Both paths reuse the same baseline sync, project identity initialization, and
optional project-fs bootstrap flow with truthful reporting for synced,
initialized, deferred, skipped, and manual follow-up items.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetProjectRoot,

    [Parameter()]
    [string]$ProjectName = '',

    [Parameter()]
    [string]$ProjectSummary = '',

    [Parameter()]
    [switch]$Apply,

    [Parameter()]
    [switch]$NewProject,

    [Parameter()]
    [switch]$SkipOptionalProjectFsBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BaselineProjectRoot {
    <#
    .SYNOPSIS
    Resolves the baseline repository root from the script path.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the baseline project root from script path: $PSScriptRoot"
    }

    return [System.IO.Path]::GetFullPath($projectRoot)
}

function Test-DirectoryIsEmpty {
    <#
    .SYNOPSIS
    Returns true when a directory is missing or has no existing entries.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Target project root exists but is not a directory: $Path"
    }

    return $null -eq (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
}

function Get-DefaultProjectNameFromTargetRoot {
    <#
    .SYNOPSIS
    Derives a readable default project name from the target directory name.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    $directoryName = Split-Path -Path ([System.IO.Path]::GetFullPath($TargetRoot)) -Leaf
    if ([string]::IsNullOrWhiteSpace($directoryName)) {
        throw "Unable to derive a default project name from target root: $TargetRoot"
    }

    $normalizedName = ($directoryName -replace '[-_]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedName)) {
        throw "Derived project name from target root is empty: $TargetRoot"
    }

    return $normalizedName
}

function Get-StartupContract {
    <#
    .SYNOPSIS
    Resolves the operator-facing startup path contract for this run.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTargetRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RequestedProjectName,

        [Parameter(Mandatory = $true)]
        [bool]$RequestedApply,

        [Parameter(Mandatory = $true)]
        [bool]$UseNewProjectMode
    )

    $resolvedTargetRoot = [System.IO.Path]::GetFullPath($RequestedTargetRoot)
    $trimmedProjectName = $RequestedProjectName.Trim()

    if ($UseNewProjectMode) {
        if (-not (Test-DirectoryIsEmpty -Path $resolvedTargetRoot)) {
            throw "New-project startup requires a missing or empty target directory: $resolvedTargetRoot"
        }

        if ([string]::IsNullOrWhiteSpace($trimmedProjectName)) {
            $trimmedProjectName = Get-DefaultProjectNameFromTargetRoot -TargetRoot $resolvedTargetRoot
        }

        return [pscustomobject]@{
            StartupPath = 'new_project_startup'
            StartupPathLabel = 'new-project startup'
            ShouldApply = $true
            RequestedApply = $RequestedApply
            ProjectName = $trimmedProjectName
            TargetRoot = $resolvedTargetRoot
        }
    }

    if ([string]::IsNullOrWhiteSpace($trimmedProjectName)) {
        throw 'ProjectName is required unless -NewProject is used.'
    }

    return [pscustomobject]@{
        StartupPath = 'existing_project_adoption'
        StartupPathLabel = 'existing/empty project adoption'
        ShouldApply = $RequestedApply
        RequestedApply = $RequestedApply
        ProjectName = $trimmedProjectName
        TargetRoot = $resolvedTargetRoot
    }
}

function Invoke-BaselineSync {
    <#
    .SYNOPSIS
    Runs the baseline sync script in safe seed-missing mode.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineRoot,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply
    )

    $syncScriptPath = Join-Path -Path $BaselineRoot -ChildPath 'scripts\sync-factory-baseline.ps1'
    if (-not (Test-Path -LiteralPath $syncScriptPath -PathType Leaf)) {
        throw "Sync script not found at: $syncScriptPath"
    }

    $arguments = @{
        TargetProjectRoot = $TargetRoot
        SeedProjectSpecificIfMissing = $true
    }

    if ($ShouldApply) {
        $arguments['Apply'] = $true
    }

    return (& $syncScriptPath @arguments)
}

function Invoke-ProjectInitialization {
    <#
    .SYNOPSIS
    Runs the project identity initializer for the selected target.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineRoot,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProjectSummary,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $initializeScriptPath = Join-Path -Path $BaselineRoot -ChildPath 'scripts\initialize-factory-project.ps1'
    if (-not (Test-Path -LiteralPath $initializeScriptPath -PathType Leaf)) {
        throw "Initialization script not found at: $initializeScriptPath"
    }

    $arguments = @{
        TargetProjectRoot = $TargetRoot
        ProjectName = $ProjectName
    }

    if (-not [string]::IsNullOrWhiteSpace($ProjectSummary)) {
        $arguments['ProjectSummary'] = $ProjectSummary
    }

    if ($IsCheckOnly) {
        $arguments['CheckOnly'] = $true
    }

    return (& $initializeScriptPath @arguments)
}

function Invoke-OptionalProjectFsBootstrap {
    <#
    .SYNOPSIS
    Attempts the optional project-fs bootstrap from the adopted target.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply,

        [Parameter(Mandatory = $true)]
        [bool]$SkipBootstrap
    )

    if ($SkipBootstrap) {
        return [pscustomobject]@{
            Status = 'skipped_by_operator'
            Message = 'Optional project-fs bootstrap was skipped by operator request.'
            ManualFollowUps = @('Run scripts\bootstrap-project-fs.ps1 inside the adopted project later if you need local project-fs MCP dependencies.')
        }
    }

    if (-not $ShouldApply) {
        return [pscustomobject]@{
            Status = 'check_only_not_run'
            Message = 'Optional project-fs bootstrap is not run in check-only mode.'
            ManualFollowUps = @('Re-run with -Apply to copy the baseline and attempt optional project-fs bootstrap.')
        }
    }

    $bootstrapScriptPath = Join-Path -Path $TargetRoot -ChildPath 'scripts\bootstrap-project-fs.ps1'
    if (-not (Test-Path -LiteralPath $bootstrapScriptPath -PathType Leaf)) {
        return [pscustomobject]@{
            Status = 'manual_follow_up_required'
            Message = 'Optional project-fs bootstrap could not run because scripts\\bootstrap-project-fs.ps1 is missing in the target project.'
            ManualFollowUps = @('Re-run adoption apply or inspect the target scripts folder before attempting project-fs bootstrap.')
        }
    }

    $bootstrapResult = & $bootstrapScriptPath
    if ($null -eq $bootstrapResult) {
        throw 'Optional project-fs bootstrap did not return a result.'
    }

    switch ([string]$bootstrapResult.Status) {
        'ready' {
            return [pscustomobject]@{
                Status = 'ready'
                Message = 'Optional project-fs bootstrap completed successfully.'
                ManualFollowUps = @()
                Details = $bootstrapResult
            }
        }
        'deferred' {
            return [pscustomobject]@{
                Status = 'deferred'
                Message = 'Optional project-fs bootstrap was deferred because prerequisites are missing.'
                ManualFollowUps = @($bootstrapResult.Remediation)
                Details = $bootstrapResult
            }
        }
        default {
            throw "Optional project-fs bootstrap returned an unsupported status: $($bootstrapResult.Status)"
        }
    }
}

function Get-CombinedManualFollowUps {
    <#
    .SYNOPSIS
    Builds a deduplicated manual follow-up list across adoption stages.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SyncResult,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$InitializationResult,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$BootstrapResult
    )

    $manualFollowUps = New-Object System.Collections.Generic.List[string]

    foreach ($followUp in @($InitializationResult.ManualFollowUps + $BootstrapResult.ManualFollowUps)) {
        if (-not [string]::IsNullOrWhiteSpace($followUp) -and -not $manualFollowUps.Contains($followUp)) {
            $manualFollowUps.Add($followUp)
        }
    }

    $projectSpecificSkipped = @($SyncResult.Plan | Where-Object {
        $_.Category -eq 'project_specific' -and $_.Status -eq 'skipped_existing'
    })

    foreach ($item in $projectSpecificSkipped) {
        $followUp = "Existing adopter-owned file kept unchanged: $($item.RelativePath)"
        if (-not $manualFollowUps.Contains($followUp)) {
            $manualFollowUps.Add($followUp)
        }
    }

    return $manualFollowUps.ToArray()
}

function Write-AdoptionReport {
    <#
    .SYNOPSIS
    Prints the final high-signal adoption report.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$StartupContract,

        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$SyncResult,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$InitializationResult,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$BootstrapResult,

        [object[]]$ManualFollowUps = @()
    )

    Write-Host ''
    Write-Host 'Factory adoption report'
    Write-Host '======================='
    Write-Host ("Startup path: {0}" -f $StartupContract.StartupPathLabel)
    Write-Host ("Target project root: {0}" -f $TargetRoot)
    Write-Host ("Project name: {0}" -f $StartupContract.ProjectName)
    Write-Host ("Mode: {0}" -f $(if ($ShouldApply) { 'apply' } else { 'check-only' }))
    if ($StartupContract.StartupPath -eq 'new_project_startup' -and -not $StartupContract.RequestedApply) {
        Write-Host '- New-project startup applies immediately by design.'
    }
    Write-Host ''
    Write-Host 'Baseline files'
    Write-Host ("- Synced or pending baseline files: {0}" -f ($SyncResult.Summary.BaselineFilesToEstablishCount + $SyncResult.Summary.FilesToUpdateCount))
    Write-Host ("- Seeded or pending project-specific files: {0}" -f $SyncResult.Summary.ProjectSpecificFilesToSeedCount)
    Write-Host ("- Already in sync: {0}" -f $SyncResult.Summary.InSyncCount)
    Write-Host ("- Skipped existing adopter-owned files: {0}" -f $SyncResult.Summary.SkippedExistingCount)
    if ($SyncResult.TargetRootCreated) {
        Write-Host '- Target root: created during apply'
    }
    elseif (-not $SyncResult.TargetRootExistedBeforeRun) {
        Write-Host '- Target root: would be created during apply'
    }
    else {
        Write-Host '- Target root: already existed'
    }

    Write-Host ''
    Write-Host 'Project identity'
    foreach ($fileResult in $InitializationResult.FileResults) {
        Write-Host ("- {0}: {1}" -f $fileResult.RelativePath, $fileResult.Status)
    }

    Write-Host ''
    Write-Host 'Optional project-fs bootstrap'
    Write-Host ("- Status: {0}" -f $BootstrapResult.Status)
    Write-Host ("- Detail: {0}" -f $BootstrapResult.Message)

    Write-Host ''
    Write-Host 'Manual follow-ups'
    if ($ManualFollowUps.Count -eq 0) {
        Write-Host '- none'
    }
    else {
        foreach ($followUp in $ManualFollowUps) {
            Write-Host "- $followUp"
        }
    }
}

function Main {
    <#
    .SYNOPSIS
    Runs the one-command adoption flow.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTargetRoot,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RequestedProjectName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RequestedProjectSummary,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldApply,

        [Parameter(Mandatory = $true)]
        [bool]$UseNewProjectMode,

        [Parameter(Mandatory = $true)]
        [bool]$SkipBootstrap
    )

    $startupContract = Get-StartupContract -RequestedTargetRoot $RequestedTargetRoot -RequestedProjectName $RequestedProjectName -RequestedApply $ShouldApply -UseNewProjectMode $UseNewProjectMode
    $baselineRoot = Get-BaselineProjectRoot
    $syncResult = Invoke-BaselineSync -BaselineRoot $baselineRoot -TargetRoot $startupContract.TargetRoot -ShouldApply $startupContract.ShouldApply
    $initializationResult = Invoke-ProjectInitialization -BaselineRoot $baselineRoot -TargetRoot $syncResult.TargetRoot -ProjectName $startupContract.ProjectName -ProjectSummary $RequestedProjectSummary -IsCheckOnly (-not $startupContract.ShouldApply)
    $bootstrapResult = Invoke-OptionalProjectFsBootstrap -TargetRoot $syncResult.TargetRoot -ShouldApply $startupContract.ShouldApply -SkipBootstrap $SkipBootstrap
    $manualFollowUps = Get-CombinedManualFollowUps -SyncResult $syncResult -InitializationResult $initializationResult -BootstrapResult $bootstrapResult

    Write-AdoptionReport -StartupContract $startupContract -TargetRoot $syncResult.TargetRoot -ShouldApply $startupContract.ShouldApply -SyncResult $syncResult -InitializationResult $initializationResult -BootstrapResult $bootstrapResult -ManualFollowUps $manualFollowUps

    return [pscustomobject]@{
        EntryPoint = Join-Path -Path $baselineRoot -ChildPath 'scripts\adopt-factory-project.ps1'
        StartupPath = $startupContract.StartupPath
        TargetRoot = $syncResult.TargetRoot
        ProjectName = $startupContract.ProjectName
        Mode = if ($startupContract.ShouldApply) { 'apply' } else { 'check-only' }
        Sync = $syncResult
        Initialization = $initializationResult
        OptionalProjectFsBootstrap = $bootstrapResult
        ManualFollowUps = $manualFollowUps
    }
}

try {
    Main -RequestedTargetRoot $TargetProjectRoot -RequestedProjectName $ProjectName -RequestedProjectSummary $ProjectSummary -ShouldApply $Apply.IsPresent -UseNewProjectMode $NewProject.IsPresent -SkipBootstrap $SkipOptionalProjectFsBootstrap.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
