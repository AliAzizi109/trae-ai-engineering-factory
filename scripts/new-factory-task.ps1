<#
.SYNOPSIS
Creates a new Factory V2 task-state JSON record with optional legacy markdown.

.DESCRIPTION
Generates a task identifier, selects the preferred model for the starting role
from the tracked routing config, and writes an authoritative JSON task file to
`.trae/factory/tasks/`, and can optionally create a matching legacy markdown
task record for readability.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Objective,

    [Parameter()]
    [string[]]$Scope = @(),

    [Parameter()]
    [string[]]$Constraints = @(),

    [Parameter()]
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$Priority = 'medium',

    [Parameter()]
    [string]$CurrentPhase = 'research',

    [Parameter()]
    [string]$CurrentRole = 'chief_orchestrator',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Status = 'open',

    [Parameter()]
    [string]$CurrentModel,

    [Parameter()]
    [switch]$CreateLegacyMarkdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sharedHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'factory-task-config-helpers.ps1'
if (-not (Test-Path -LiteralPath $sharedHelperPath -PathType Leaf)) {
    throw "Required shared helper script not found: $sharedHelperPath"
}
. $sharedHelperPath

function Get-ProjectRoot {
    [OutputType([string])]
    param()

    return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function New-TaskId {
    [OutputType([string])]
    param()

    return 'TASK-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function ConvertTo-SafeSlug {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $slug = $Value.ToLowerInvariant()
    $slug = [System.Text.RegularExpressions.Regex]::Replace($slug, '[^a-z0-9]+', '-')
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'task'
    }

    return $slug
}

function Write-JsonFile {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [hashtable]$Value
    )

    $content = $Value | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $content + [Environment]::NewLine, $utf8NoBom)
}

function Get-SelectedModel {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RoutingConfig,

        [Parameter(Mandatory = $true)]
        [string]$Role,

        [Parameter()]
        [string]$ExplicitModel
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitModel)) {
        return $ExplicitModel
    }

    $roleConfig = $RoutingConfig.role_routes[$Role]
    if ($null -eq $roleConfig) {
        throw "Role '$Role' was not found in model routing config."
    }

    return [string]$roleConfig.preferred_model
}

function Main {
    [OutputType([void])]
    param()

    $projectRoot = Get-ProjectRoot
    $templatePath = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\templates\task-state.template.json'
    $roleSystemPath = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\config\role-system.json'
    $handoffsPath = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\config\handoffs.json'
    $routingPath = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\config\model-routing.json'
    $taskDirectory = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\tasks'

    $template = Read-JsonHashtable -Path $templatePath
    $roleSystem = Read-JsonHashtable -Path $roleSystemPath
    $handoffs = Read-JsonHashtable -Path $handoffsPath
    $routing = Read-JsonHashtable -Path $routingPath
    $allowedRoles = @($roleSystem.roles.Keys | ForEach-Object { [string]$_ })
    $allowedCreationPhases = @(Get-AllowedCreationPhases -HandoffConfig $handoffs)
    $taskId = New-TaskId
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')
    $slug = ConvertTo-SafeSlug -Value $Objective
    $taskPath = Join-Path -Path $taskDirectory -ChildPath ('{0}-{1}.json' -f $taskId.ToLowerInvariant(), $slug)

    if (Test-Path -LiteralPath $taskPath) {
        throw "Task file already exists: $taskPath"
    }

    Assert-ConfigDefinedValue -FieldName 'CurrentRole' -Value $CurrentRole -AllowedValues $allowedRoles -SourcePath $roleSystemPath
    Assert-ConfigDefinedValue -FieldName 'CurrentPhase' -Value $CurrentPhase -AllowedValues $allowedCreationPhases -SourcePath $handoffsPath
    $selectedModel = Get-SelectedModel -RoutingConfig $routing -Role $CurrentRole -ExplicitModel $CurrentModel

    $template.task_id = $taskId
    $template.objective = $Objective
    $template.scope = @($Scope | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $template.constraints = @($Constraints | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $template.findings = @()
    $template.remaining_work = @()
    $template.evidence = @()
    $template.priority = $Priority
    $template.current_phase = $CurrentPhase
    $template.current_role = $CurrentRole
    $template.current_model = $selectedModel
    $template.fallback_used = $false
    $template.status = $Status
    $template.review_result = 'pending'
    $template.security_result = 'pending'
    $template.qa_result = 'pending'
    $template.qa_verification = @{
        status = 'pending'
        verdict_reason = ''
        verifier_role = ''
        invocation_path = ''
        execution_mode = ''
        evidence_sufficiency = 'insufficient'
        blocking_checks = @()
        advisory_checks = @()
        passed_checks = @()
        failed_checks = @()
        skipped_checks = @()
        not_possible_checks = @()
        commands = @()
        artifacts = @()
        limitations = @()
    }
    $template.retry_count = 0
    $template.blocker = ''
    $template.next_automatic_action = 'Continue via the next documented handoff.'
    $template.escalation_reason = ''
    $template.verification_summary = ''
    $template.final_outcome = ''
    $template.created_at = $timestamp
    $template.updated_at = $timestamp
    $template.execution_log = @(
        @{
            timestamp = $timestamp
            role = 'task_state_coordinator'
            message = "Task created for role '$CurrentRole' in phase '$CurrentPhase'."
        }
    )
    $template.events = @(
        @{
            timestamp = $timestamp
            type = 'task_created'
            role = 'task_state_coordinator'
            summary = $Objective
        }
    )
    $template.model_attempts = @(
        @{
            timestamp = $timestamp
            role = $CurrentRole
            model = $selectedModel
            outcome = 'selected'
            fallback_used = $false
        }
    )

    Write-JsonFile -Path $taskPath -Value $template

    Write-Host "Created factory task: $taskId"
    Write-Host "Task file: $taskPath"
    Write-Host "Current role: $CurrentRole"
    Write-Host "Current model: $selectedModel"

    if ($CreateLegacyMarkdown.IsPresent) {
        $legacyTemplatePath = Get-FactoryPath -ProjectRoot $projectRoot -RelativePath '.trae\factory\templates\task.md'
        $legacyTaskPath = [System.IO.Path]::ChangeExtension($taskPath, '.md')
        if (Test-Path -LiteralPath $legacyTaskPath) {
            throw "Legacy markdown task file already exists: $legacyTaskPath"
        }
        $legacyTemplateContent = [System.IO.File]::ReadAllText($legacyTemplatePath, [System.Text.Encoding]::UTF8)
        $legacyTaskContent = $legacyTemplateContent.Replace('TASK-YYYYMMDD-HHMMSS', $taskId)
        $legacyTaskContent = $legacyTaskContent.Replace('[objective]', $Objective)
        $legacyTaskContent = $legacyTaskContent.Replace('- Phase: Research', "- Phase: $CurrentPhase")
        $legacyTaskContent = $legacyTaskContent.Replace('- Responsible agent: solo/main', "- Responsible agent: $CurrentRole")
        $legacyTaskContent = $legacyTaskContent.Replace('- Status: Open', "- Status: $Status")
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($legacyTaskPath, $legacyTaskContent, $utf8NoBom)
        Write-Host "Legacy markdown: $legacyTaskPath"
    }
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
