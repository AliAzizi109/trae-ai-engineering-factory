<#
.SYNOPSIS
Prints an operator-focused dashboard for tracked factory tasks.

.DESCRIPTION
Scans `.trae/factory/tasks/*.json`, tolerates older or variant task schemas,
selects a specific task or the active/latest task when none is requested, and
returns either a human-readable dashboard or JSON via `-AsJson`.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TaskPath,

    [Parameter()]
    [string]$TaskId,

    [Parameter()]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Resolves the repository root from the script location.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return [System.IO.Path]::GetFullPath($projectRoot)
}

function Normalize-CanonicalPath {
    <#
    .SYNOPSIS
    Returns a normalized canonical filesystem path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    return $fullPath.TrimEnd('\')
}

function Get-TaskDirectory {
    <#
    .SYNOPSIS
    Returns the canonical tracked task directory.
    #>
    [OutputType([string])]
    param()

    $taskDirectory = Join-Path -Path (Get-ProjectRoot) -ChildPath '.trae\factory\tasks'
    if (-not (Test-Path -LiteralPath $taskDirectory -PathType Container)) {
        throw "Task directory not found: $taskDirectory"
    }

    return Normalize-CanonicalPath -Path $taskDirectory
}

function Assert-TaskPathInScope {
    <#
    .SYNOPSIS
    Ensures a path stays inside the tracked task directory.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $taskDirectory = Get-TaskDirectory
    $normalizedPath = Normalize-CanonicalPath -Path $Path
    $taskDirectoryPrefix = $taskDirectory + '\'

    if ($normalizedPath.Equals($taskDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    if (-not $normalizedPath.StartsWith($taskDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "TaskPath must stay within the tracked task directory: $taskDirectory"
    }
}

function Resolve-RequestedTaskPath {
    <#
    .SYNOPSIS
    Resolves and validates an explicitly requested task path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $taskDirectory = Get-TaskDirectory
    $candidatePath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        $projectRelativePath = Join-Path -Path (Get-ProjectRoot) -ChildPath $Path
        if (Test-Path -LiteralPath $projectRelativePath -PathType Leaf) {
            $projectRelativePath
        }
        else {
            Join-Path -Path $taskDirectory -ChildPath $Path
        }
    }

    $fullPath = Normalize-CanonicalPath -Path $candidatePath
    Assert-TaskPathInScope -Path $fullPath

    if ([System.IO.Path]::GetExtension($fullPath) -ne '.json') {
        throw "TaskPath must target a JSON file: $fullPath"
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Task file not found: $fullPath"
    }

    return $fullPath
}

function Get-SummaryScriptPath {
    <#
    .SYNOPSIS
    Returns the path to the normalized task-summary script.
    #>
    [OutputType([string])]
    param()

    $summaryScriptPath = Join-Path -Path (Get-ProjectRoot) -ChildPath 'scripts\get-factory-task-summary.ps1'
    if (-not (Test-Path -LiteralPath $summaryScriptPath -PathType Leaf)) {
        throw "Task summary script not found: $summaryScriptPath"
    }

    return $summaryScriptPath
}

function ConvertTo-HashtableObject {
    <#
    .SYNOPSIS
    Recursively converts JSON objects into native PowerShell hashtables and arrays.
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $table = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $table[[string]$key] = ConvertTo-HashtableObject -Value $Value[$key]
        }

        return $table
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-HashtableObject -Value $item))
        }

        return ,$items.ToArray()
    }

    if ($null -ne $Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and $Value -isnot [string]) {
        $table = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-HashtableObject -Value $property.Value
        }

        return $table
    }

    return $Value
}

function Get-TaskSummary {
    <#
    .SYNOPSIS
    Loads the normalized summary for a task by invoking the summary script.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedTaskPath
    )

    $summaryScriptPath = Get-SummaryScriptPath
    $json = & $summaryScriptPath -TaskPath $ResolvedTaskPath -AsJson

    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        throw "Task summary script returned no output for: $ResolvedTaskPath"
    }

    return [hashtable](ConvertTo-HashtableObject -Value ($json | ConvertFrom-Json -ErrorAction Stop))
}

function Get-TrackedTaskPaths {
    <#
    .SYNOPSIS
    Returns tracked task JSON paths, excluding synchronized backup files.
    #>
    [OutputType([string[]])]
    param()

    $taskDirectory = Get-TaskDirectory
    return @(Get-ChildItem -LiteralPath $taskDirectory -Filter '*.json' -File -ErrorAction Stop |
            Where-Object { $_.Name -notlike '.*.last-known-good.json' } |
            Sort-Object -Property LastWriteTimeUtc -Descending |
            ForEach-Object { $_.FullName })
}

function Get-OpenTaskCounts {
    <#
    .SYNOPSIS
    Computes repo-level counts for open, blocked, and awaiting-approval tasks.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    return [ordered]@{
        open = @($TaskSummaries | Where-Object { $_.status -in @('open', 'in_progress') }).Count
        blocked = @($TaskSummaries | Where-Object { $_.status -eq 'blocked' -or $_.blocker_state -eq 'blocked' }).Count
        awaiting_approval = @($TaskSummaries | Where-Object { $_.approval_required -eq $true }).Count
    }
}

function Select-DefaultTask {
    <#
    .SYNOPSIS
    Selects the active task if present, otherwise the latest task.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    $activeTask = $TaskSummaries | Where-Object { $_.status -in @('in_progress', 'open', 'blocked', 'awaiting_human_approval') } |
        Sort-Object -Property updated_at -Descending |
        Select-Object -First 1

    if ($null -ne $activeTask) {
        return [hashtable]$activeTask
    }

    return [hashtable]($TaskSummaries | Sort-Object -Property updated_at -Descending | Select-Object -First 1)
}

function Write-TextDashboard {
    <#
    .SYNOPSIS
    Writes a concise human-readable operator dashboard.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Dashboard
    )

    $task = $Dashboard.selected_task
    $latestEvent = if ($null -ne $task.latest_event) {
        if (-not [string]::IsNullOrWhiteSpace([string]$task.latest_event.summary)) {
            [string]$task.latest_event.summary
        }
        else {
            [string]$task.latest_event.message
        }
    }
    else {
        'none'
    }

    Write-Host "Operator status source: $($Dashboard.selection_mode)"
    Write-Host "Task ID: $($task.task_id)"
    Write-Host "Task state: $($task.status)"
    Write-Host "Current role: $($task.current_role)"
    Write-Host "Current model: $($task.current_model)"
    Write-Host "Fallback usage: $($task.fallback_used)"
    Write-Host "Blockers: $($task.blocker)"
    Write-Host "Next automatic step: $($task.next_automatic_action)"
    Write-Host "Approval need: $($task.approval_required)"
    Write-Host "Review/Security/QA: $($task.review_result) / $($task.security_result) / $($task.qa_result)"
    Write-Host "QA quality gate: $($task.qa_quality_gate)"
    Write-Host "QA evidence sufficiency: $($task.qa_evidence_sufficiency)"
    Write-Host "QA checks blocking/passed/failed/skipped/not-possible: $($task.qa_blocking_check_count) / $($task.qa_passed_check_count) / $($task.qa_failed_check_count) / $($task.qa_skipped_check_count) / $($task.qa_not_possible_check_count)"
    Write-Host "Latest event: $latestEvent"
    Write-Host "Counts open/blocked/awaiting approval: $($Dashboard.task_counts.open) / $($Dashboard.task_counts.blocked) / $($Dashboard.task_counts.awaiting_approval)"
    Write-Host "Task file: $($task.task_path)"
}

function Main {
    <#
    .SYNOPSIS
    Produces an operator dashboard for tracked tasks.
    #>
    [OutputType([void])]
    param()

    $taskPaths = Get-TrackedTaskPaths
    if (@($taskPaths).Count -eq 0) {
        throw 'No tracked task JSON files were found under .trae/factory/tasks/.'
    }

    $taskSummaries = @()
    foreach ($path in $taskPaths) {
        $taskSummaries += @(Get-TaskSummary -ResolvedTaskPath $path)
    }

    $selectedTask = $null
    $selectionMode = 'active_or_latest'
    if (-not [string]::IsNullOrWhiteSpace($TaskPath)) {
        $selectedTask = Get-TaskSummary -ResolvedTaskPath (Resolve-RequestedTaskPath -Path $TaskPath)
        $selectionMode = 'explicit_task_path'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $selectedTask = $taskSummaries | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1
        if ($null -eq $selectedTask) {
            throw "Task ID not found: $TaskId"
        }

        $selectedTask = [hashtable]$selectedTask
        $selectionMode = 'explicit_task_id'
    }
    else {
        $selectedTask = Select-DefaultTask -TaskSummaries $taskSummaries
    }

    $dashboard = [ordered]@{
        repository_root = Get-ProjectRoot
        task_directory = Get-TaskDirectory
        selection_mode = $selectionMode
        selected_task = $selectedTask
        task_counts = Get-OpenTaskCounts -TaskSummaries $taskSummaries
        task_count_total = @($taskSummaries).Count
    }

    if ($AsJson.IsPresent) {
        Write-Output ($dashboard | ConvertTo-Json -Depth 20)
        return
    }

    Write-TextDashboard -Dashboard $dashboard
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Main
    }
    catch {
        Write-Error $_
        exit 1
    }
}
