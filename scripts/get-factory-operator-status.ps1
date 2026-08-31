<#
.SYNOPSIS
Prints an operator-focused dashboard for tracked factory tasks.

.DESCRIPTION
Scans `.trae/factory/tasks/*.json`, resolves one normalized summary per task via
`get-factory-task-summary.ps1`, distinguishes the execution focus task from
attention-needed tasks, and returns either a human-readable dashboard or JSON
via `-AsJson`.
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
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return [System.IO.Path]::GetFullPath($projectRoot)
}

function Normalize-CanonicalPath {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\')
}

function Get-TaskDirectory {
    [OutputType([string])]
    param()

    $taskDirectory = Join-Path -Path (Get-ProjectRoot) -ChildPath '.trae\factory\tasks'
    if (-not (Test-Path -LiteralPath $taskDirectory -PathType Container)) {
        throw "Task directory not found: $taskDirectory"
    }

    return Normalize-CanonicalPath -Path $taskDirectory
}

function Assert-TaskPathInScope {
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
    [OutputType([string])]
    param()

    $summaryScriptPath = Join-Path -Path (Get-ProjectRoot) -ChildPath 'scripts\get-factory-task-summary.ps1'
    if (-not (Test-Path -LiteralPath $summaryScriptPath -PathType Leaf)) {
        throw "Task summary script not found: $summaryScriptPath"
    }

    return $summaryScriptPath
}

function ConvertTo-HashtableObject {
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
    [OutputType([string[]])]
    param()

    $taskDirectory = Get-TaskDirectory
    return @(Get-ChildItem -LiteralPath $taskDirectory -Filter '*.json' -File -ErrorAction Stop |
            Where-Object { $_.Name -notlike '.*.last-known-good.json' } |
            Sort-Object -Property LastWriteTimeUtc -Descending |
            ForEach-Object { $_.FullName })
}

function ConvertTo-NullableDateTimeOffset {
    [OutputType([object])]
    param(
        [AllowNull()]
        [string]$Timestamp
    )

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        return $null
    }

    try {
        return [System.DateTimeOffset]::Parse(
            $Timestamp,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal)
    }
    catch {
        return $null
    }
}

function Get-TaskSortKey {
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TaskSummary
    )

    foreach ($fieldName in @('recent_activity_sort_key', 'updated_at_sort_key', 'latest_event_sort_key')) {
        if ($TaskSummary.ContainsKey($fieldName) -and $null -ne $TaskSummary[$fieldName]) {
            return [double]$TaskSummary[$fieldName]
        }
    }

    $parsedUpdatedAt = ConvertTo-NullableDateTimeOffset -Timestamp ([string]$TaskSummary.updated_at)
    if ($null -ne $parsedUpdatedAt) {
        return [double]$parsedUpdatedAt.UtcTicks
    }

    return [double]0
}

function Sort-TaskSummariesByRecency {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    return @($TaskSummaries | Sort-Object -Property @{ Expression = { Get-TaskSortKey -TaskSummary ([hashtable]$_) } }, @{ Expression = { [string]$_.task_id } } -Descending)
}

function Get-TaskIdentityKey {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TaskSummary
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$TaskSummary.task_id)) {
        return [string]$TaskSummary.task_id
    }

    return [string]$TaskSummary.task_path
}

function Get-LatestUniqueTaskSummaries {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[object]

    foreach ($taskSummary in (Sort-TaskSummariesByRecency -TaskSummaries $TaskSummaries)) {
        $identityKey = Get-TaskIdentityKey -TaskSummary ([hashtable]$taskSummary)
        if ($seen.Add($identityKey)) {
            [void]$unique.Add($taskSummary)
        }
    }

    return ,$unique.ToArray()
}

function Get-DuplicateTaskIdDetails {
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    $details = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($TaskSummaries | Group-Object -Property { Get-TaskIdentityKey -TaskSummary ([hashtable]$_) } | Where-Object { $_.Count -gt 1 })) {
        $sortedGroup = Sort-TaskSummariesByRecency -TaskSummaries @($group.Group)
        $details.Add([ordered]@{
                task_id = [string]$group.Name
                kept_task_path = [string]$sortedGroup[0].task_path
                kept_updated_at = [string]$sortedGroup[0].updated_at
                shadowed_task_paths = @($sortedGroup | Select-Object -Skip 1 | ForEach-Object { [string]$_.task_path })
            })
    }

    return ,$details.ToArray()
}

function New-TaskCard {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TaskSummary
    )

    return [ordered]@{
        task_id = [string]$TaskSummary.task_id
        objective = [string]$TaskSummary.objective
        status = [string]$TaskSummary.status
        current_phase = [string]$TaskSummary.current_phase
        current_role = [string]$TaskSummary.current_role
        current_model = [string]$TaskSummary.current_model
        fallback_used = [bool]$TaskSummary.fallback_used
        approval_required = [bool]$TaskSummary.approval_required
        operator_attention_state = [string]$TaskSummary.operator_attention_state
        primary_operator_action = [string]$TaskSummary.primary_operator_action
        next_automatic_action = [string]$TaskSummary.next_automatic_action
        blocker = [string]$TaskSummary.blocker
        updated_at = [string]$TaskSummary.updated_at
        latest_event_summary = [string]$TaskSummary.latest_event_summary
        model_route_summary = [string]$TaskSummary.model_route_summary
        current_model_route_state = [string]$TaskSummary.current_model_route_state
        preferred_model_for_role = [string]$TaskSummary.preferred_model_for_role
        next_fallback_model = [string]$TaskSummary.next_fallback_model
        task_path = [string]$TaskSummary.task_path
    }
}

function Get-TaskCounts {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    $openOnlyTasks = @($TaskSummaries | Where-Object { $_.status -eq 'open' })
    $inProgressTasks = @($TaskSummaries | Where-Object { $_.status -eq 'in_progress' })
    $blockedTasks = @($TaskSummaries | Where-Object { $_.operator_attention_state -eq 'blocked' -or $_.status -eq 'blocked' })
    $approvalTasks = @($TaskSummaries | Where-Object { $_.approval_required -eq $true })
    $completedTasks = @($TaskSummaries | Where-Object { $_.status -eq 'completed' })

    return [ordered]@{
        open = $openOnlyTasks.Count + $inProgressTasks.Count
        open_only = $openOnlyTasks.Count
        in_progress = $inProgressTasks.Count
        blocked = $blockedTasks.Count
        awaiting_approval = $approvalTasks.Count
        completed = $completedTasks.Count
        attention_needed = @($TaskSummaries | Where-Object { $_.approval_required -eq $true -or $_.operator_attention_state -eq 'blocked' }).Count
    }
}

function Select-FocusTask {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$TaskSummaries
    )

    $sorted = Sort-TaskSummariesByRecency -TaskSummaries $TaskSummaries
    $inProgressTasks = @($sorted | Where-Object { $_.status -eq 'in_progress' })
    $openOnlyTasks = @($sorted | Where-Object { $_.status -eq 'open' })
    $approvalTasks = @($sorted | Where-Object { $_.approval_required -eq $true })
    $blockedTasks = @($sorted | Where-Object { $_.operator_attention_state -eq 'blocked' -or $_.status -eq 'blocked' })

    if ($inProgressTasks.Count -gt 0) {
        return [ordered]@{
            task = [hashtable]$inProgressTasks[0]
            reason = 'Showing the most recently active in-progress task.'
            mode = 'recent_in_progress'
        }
    }

    if ($openOnlyTasks.Count -gt 0) {
        return [ordered]@{
            task = [hashtable]$openOnlyTasks[0]
            reason = 'No task is in progress, so the newest open task is shown as the current execution focus.'
            mode = 'newest_open'
        }
    }

    if ($approvalTasks.Count -gt 0) {
        return [ordered]@{
            task = [hashtable]$approvalTasks[0]
            reason = 'No execution task is active, so the newest approval-needed task is shown for human attention.'
            mode = 'approval_queue'
        }
    }

    if ($blockedTasks.Count -gt 0) {
        return [ordered]@{
            task = [hashtable]$blockedTasks[0]
            reason = 'No open execution task remains, so the newest blocked task is shown.'
            mode = 'blocked_queue'
        }
    }

    return [ordered]@{
        task = if ($sorted.Count -gt 0) { [hashtable]$sorted[0] } else { $null }
        reason = 'Showing the newest available task.'
        mode = 'newest_available'
    }
}

function Write-TextDashboard {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Dashboard
    )

    $task = $Dashboard.focus_task

    Write-Host "Operator status source: $($Dashboard.selection_mode)"
    Write-Host "Focus reason: $($Dashboard.focus_reason)"

    if ($null -ne $task) {
        Write-Host "Task ID: $($task.task_id)"
        Write-Host "Task state: $($task.status)"
        Write-Host "Operator attention state: $($task.operator_attention_state)"
        Write-Host "Current role: $($task.current_role)"
        Write-Host "Current model: $($task.current_model)"
        Write-Host "Model route: $($task.model_route_summary)"
        Write-Host "Fallback usage: $($task.fallback_used)"
        Write-Host "Blockers: $($task.blocker)"
        Write-Host "Primary operator action: $($task.primary_operator_action)"
        Write-Host "Next automatic step: $($task.next_automatic_action)"
        Write-Host "Approval need: $($task.approval_required)"
        Write-Host "Latest event: $($task.latest_event_summary)"
        Write-Host "Updated at: $($task.updated_at)"
        Write-Host "Task file: $($task.task_path)"
    }

    Write-Host "Counts open/open-only/in-progress/blocked/awaiting approval/completed: $($Dashboard.task_counts.open) / $($Dashboard.task_counts.open_only) / $($Dashboard.task_counts.in_progress) / $($Dashboard.task_counts.blocked) / $($Dashboard.task_counts.awaiting_approval) / $($Dashboard.task_counts.completed)"
    if (@($Dashboard.duplicate_task_ids).Count -gt 0) {
        Write-Host "Collapsed duplicate task IDs: $($Dashboard.duplicate_task_ids -join ', ')"
        foreach ($detail in @($Dashboard.duplicate_task_details)) {
            Write-Host ("- Keeping newest record for {0}: {1}" -f $detail.task_id, $detail.kept_task_path)
            foreach ($shadowedPath in @($detail.shadowed_task_paths)) {
                Write-Host ("  shadowed: {0}" -f $shadowedPath)
            }
        }
    }

    $attentionTaskCards = @($Dashboard.attention_needed_tasks)
    if ($attentionTaskCards.Count -gt 0) {
        Write-Host 'Attention-needed tasks:'
        foreach ($card in $attentionTaskCards) {
            Write-Host ("- [{0}] {1} | {2}" -f $card.operator_attention_state, $card.task_id, $card.objective)
        }
    }
    else {
        Write-Host 'Attention-needed tasks: none'
    }

    Write-Host 'Recent tasks:'
    foreach ($card in @($Dashboard.recent_tasks)) {
        Write-Host ("- [{0}] {1} | {2}" -f $card.status, $card.task_id, $card.objective)
    }
}

function Main {
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

    $sortedSummaries = Sort-TaskSummariesByRecency -TaskSummaries $taskSummaries
    $uniqueSortedSummaries = Get-LatestUniqueTaskSummaries -TaskSummaries $sortedSummaries
    $duplicateTaskIds = @($sortedSummaries | Group-Object -Property { Get-TaskIdentityKey -TaskSummary ([hashtable]$_) } | Where-Object { $_.Count -gt 1 } | ForEach-Object { [string]$_.Name })
    $duplicateTaskDetails = Get-DuplicateTaskIdDetails -TaskSummaries $sortedSummaries
    $taskCounts = Get-TaskCounts -TaskSummaries $uniqueSortedSummaries
    $attentionNeededTasks = @($uniqueSortedSummaries | Where-Object { $_.approval_required -eq $true -or $_.operator_attention_state -eq 'blocked' } | Select-Object -First 5 | ForEach-Object { New-TaskCard -TaskSummary ([hashtable]$_) })
    $recentTasks = @($uniqueSortedSummaries | Select-Object -First 5 | ForEach-Object { New-TaskCard -TaskSummary ([hashtable]$_) })
    $newestTask = if ($uniqueSortedSummaries.Count -gt 0) { New-TaskCard -TaskSummary ([hashtable]$uniqueSortedSummaries[0]) } else { $null }

    $focusSelection = $null
    $selectionMode = 'active_or_latest'
    if (-not [string]::IsNullOrWhiteSpace($TaskPath)) {
        $resolvedTaskPath = Resolve-RequestedTaskPath -Path $TaskPath
        $selectedTask = $sortedSummaries | Where-Object { $_.task_path -eq $resolvedTaskPath } | Select-Object -First 1
        if ($null -eq $selectedTask) {
            throw "Task path not found in tracked summaries: $resolvedTaskPath"
        }

        $focusSelection = [ordered]@{
            task = [hashtable]$selectedTask
            reason = 'Showing the explicitly requested task path.'
            mode = 'explicit_task_path'
        }
        $selectionMode = 'explicit_task_path'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $selectedTask = $sortedSummaries | Where-Object { $_.task_id -eq $TaskId } | Select-Object -First 1
        if ($null -eq $selectedTask) {
            throw "Task ID not found: $TaskId"
        }

        $focusSelection = [ordered]@{
            task = [hashtable]$selectedTask
            reason = 'Showing the explicitly requested task ID.'
            mode = 'explicit_task_id'
        }
        $selectionMode = 'explicit_task_id'
    }
    else {
        $focusSelection = Select-FocusTask -TaskSummaries $uniqueSortedSummaries
        $selectionMode = [string]$focusSelection.mode
    }

    $focusTaskCard = if ($null -ne $focusSelection.task) { New-TaskCard -TaskSummary ([hashtable]$focusSelection.task) } else { $null }

    $dashboard = [ordered]@{
        repository_root = Get-ProjectRoot
        task_directory = Get-TaskDirectory
        selection_mode = $selectionMode
        focus_reason = [string]$focusSelection.reason
        focus_task = $focusTaskCard
        selected_task = $focusTaskCard
        newest_task = $newestTask
        duplicate_task_ids = $duplicateTaskIds
        duplicate_task_details = $duplicateTaskDetails
        attention_needed_tasks = $attentionNeededTasks
        recent_tasks = $recentTasks
        task_counts = $taskCounts
        task_count_total = @($uniqueSortedSummaries).Count
        raw_task_record_count = @($sortedSummaries).Count
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
