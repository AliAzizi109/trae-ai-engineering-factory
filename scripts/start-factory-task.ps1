<#
.SYNOPSIS
Creates a factory task and immediately prints the most useful summaries.

.DESCRIPTION
Wraps `new-factory-task.ps1`, `get-factory-task-summary.ps1`, and
`get-factory-operator-status.ps1` in a single low-friction entrypoint without
introducing a parallel workflow. The script creates one task, resolves the emitted
task path, then runs the existing summary scripts sequentially.
#>

[CmdletBinding()]
param(
    [string]$Objective,

    [Parameter()]
    [string[]]$Scope = @(),

    [Parameter()]
    [string[]]$Constraints = @(),

    [Parameter()]
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$Priority = 'medium',

    [Parameter()]
    [ValidateSet('research', 'plan', 'implement', 'review', 'security_review', 'qa', 'release_gate', 'human_approval')]
    [string]$CurrentPhase = 'research',

    [Parameter()]
    [ValidateSet('chief_orchestrator', 'planner_architect', 'research_docs', 'coder_implementer', 'code_reviewer', 'security_reviewer', 'qa_test_verifier', 'git_release_gatekeeper', 'task_state_coordinator', 'lightweight_routine')]
    [string]$CurrentRole = 'chief_orchestrator',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Status = 'open',

    [Parameter()]
    [string]$CurrentModel,

    [Parameter()]
    [switch]$CreateLegacyMarkdown,

    [Parameter()]
    [switch]$CheckOnly
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

function Get-ScriptPath {
    <#
    .SYNOPSIS
    Resolves a required sibling script path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )

    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Required script not found: $scriptPath"
    }

    return $scriptPath
}

function Get-TaskDirectory {
    <#
    .SYNOPSIS
    Resolves the tracked task directory.
    #>
    [OutputType([string])]
    param()

    $taskDirectory = Join-Path -Path (Get-ProjectRoot) -ChildPath '.trae\\factory\\tasks'
    if (-not (Test-Path -LiteralPath $taskDirectory -PathType Container)) {
        throw "Tracked task directory not found: $taskDirectory"
    }

    return [System.IO.Path]::GetFullPath($taskDirectory)
}

function Get-TaskFileSnapshot {
    <#
    .SYNOPSIS
    Returns the current task JSON files in the tracked task directory.
    #>
    [OutputType([System.IO.FileInfo[]])]
    param()

    $taskDirectory = Get-TaskDirectory
    return @(Get-ChildItem -LiteralPath $taskDirectory -Filter '*.json' -File | Sort-Object LastWriteTimeUtc, Name)
}

function Resolve-CreatedTaskPath {
    <#
    .SYNOPSIS
    Resolves the created task path from before/after task directory snapshots.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$BeforeSnapshot,

        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$AfterSnapshot
    )

    $beforePaths = @{}
    foreach ($item in $BeforeSnapshot) {
        $beforePaths[$item.FullName] = $true
    }

    $newFiles = @($AfterSnapshot | Where-Object { -not $beforePaths.ContainsKey($_.FullName) })
    if ($newFiles.Count -eq 1) {
        return $newFiles[0].FullName
    }

    if ($newFiles.Count -gt 1) {
        throw 'More than one new task JSON file was detected. Refusing to guess which task was created.'
    }

    throw 'No new task JSON file was detected after new-factory-task.ps1 completed.'
}

function Invoke-TaskCreation {
    <#
    .SYNOPSIS
    Runs the task creation script and returns the created task path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectiveText,

        [Parameter(Mandatory = $true)]
        [string[]]$TaskScope,

        [Parameter(Mandatory = $true)]
        [string[]]$TaskConstraints,

        [Parameter(Mandatory = $true)]
        [string]$TaskPriority,

        [Parameter(Mandatory = $true)]
        [string]$TaskPhase,

        [Parameter(Mandatory = $true)]
        [string]$TaskRole,

        [Parameter(Mandatory = $true)]
        [string]$TaskStatus,

        [Parameter()]
        [string]$TaskModel,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldCreateLegacyMarkdown
    )

    $beforeSnapshot = @(Get-TaskFileSnapshot)
    $createScriptPath = Get-ScriptPath -ScriptName 'new-factory-task.ps1'
    $scriptParameters = @{
        Objective = $ObjectiveText
        Scope = $TaskScope
        Constraints = $TaskConstraints
        Priority = $TaskPriority
        CurrentPhase = $TaskPhase
        CurrentRole = $TaskRole
        Status = $TaskStatus
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskModel)) {
        $scriptParameters['CurrentModel'] = $TaskModel
    }

    if ($ShouldCreateLegacyMarkdown) {
        $scriptParameters['CreateLegacyMarkdown'] = $true
    }

    & $createScriptPath @scriptParameters

    $afterSnapshot = @(Get-TaskFileSnapshot)
    return Resolve-CreatedTaskPath -BeforeSnapshot $beforeSnapshot -AfterSnapshot $afterSnapshot
}

function Invoke-TaskSummary {
    <#
    .SYNOPSIS
    Runs the task summary script for the created task.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskPath
    )

    $summaryScriptPath = Get-ScriptPath -ScriptName 'get-factory-task-summary.ps1'
    & $summaryScriptPath -TaskPath $TaskPath
}

function Invoke-OperatorStatus {
    <#
    .SYNOPSIS
    Runs the operator status script for the created task.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskPath
    )

    $statusScriptPath = Get-ScriptPath -ScriptName 'get-factory-operator-status.ps1'
    & $statusScriptPath -TaskPath $TaskPath
}

function Main {
    <#
    .SYNOPSIS
    Creates a task and prints the immediate follow-up summaries.
    #>
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$TaskObjective,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$TaskScope,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$TaskConstraints,

        [Parameter(Mandatory = $true)]
        [string]$TaskPriority,

        [Parameter(Mandatory = $true)]
        [string]$TaskPhase,

        [Parameter(Mandatory = $true)]
        [string]$TaskRole,

        [Parameter(Mandatory = $true)]
        [string]$TaskStatus,

        [Parameter()]
        [string]$TaskModel,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldCreateLegacyMarkdown,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $projectRoot = Get-ProjectRoot

    if ($IsCheckOnly) {
        Write-Host 'Start-factory-task check passed.'
        Write-Host ("Project root: {0}" -f $projectRoot)
        Write-Host ('Create script: {0}' -f (Get-ScriptPath -ScriptName 'new-factory-task.ps1'))
        Write-Host ('Follow-up: {0}' -f (Get-ScriptPath -ScriptName 'get-factory-task-summary.ps1'))
        Write-Host ('Follow-up: {0}' -f (Get-ScriptPath -ScriptName 'get-factory-operator-status.ps1'))
        return
    }

    if ([string]::IsNullOrWhiteSpace($TaskObjective)) {
        throw 'Objective is required unless -CheckOnly is used.'
    }

    $taskPath = Invoke-TaskCreation -ObjectiveText $TaskObjective -TaskScope $TaskScope -TaskConstraints $TaskConstraints -TaskPriority $TaskPriority -TaskPhase $TaskPhase -TaskRole $TaskRole -TaskStatus $TaskStatus -TaskModel $TaskModel -ShouldCreateLegacyMarkdown $ShouldCreateLegacyMarkdown

    Write-Host 'Task created successfully.'
    Write-Host ("Task path: {0}" -f $taskPath)
    Invoke-TaskSummary -TaskPath $taskPath
    Invoke-OperatorStatus -TaskPath $taskPath
}

try {
    Main -TaskObjective $Objective -TaskScope $Scope -TaskConstraints $Constraints -TaskPriority $Priority -TaskPhase $CurrentPhase -TaskRole $CurrentRole -TaskStatus $Status -TaskModel $CurrentModel -ShouldCreateLegacyMarkdown $CreateLegacyMarkdown.IsPresent -IsCheckOnly $CheckOnly.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
