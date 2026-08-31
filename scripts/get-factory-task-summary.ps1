<#
.SYNOPSIS
Prints a normalized operational summary for a factory task JSON record.

.DESCRIPTION
Reads a task record from `.trae/factory/tasks/`, preserves strong path and
handle validation, falls back only to the synchronized last-known-good backup
when needed, normalizes older or variant task schemas, and prints either a
human-readable summary or a JSON payload.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath,

    [Parameter()]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-HandlePathInterop {
    <#
    .SYNOPSIS
    Loads the Win32 handle-path helper once per session.
    #>
    [OutputType([void])]
    param()

    if (-not ('FactoryHandlePathInterop' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class FactoryHandlePathInterop
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFinalPathNameByHandle(
        SafeFileHandle hFile,
        System.Text.StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags);
}
'@
    }
}

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

function Convert-HandlePathToCanonicalPath {
    <#
    .SYNOPSIS
    Normalizes a Win32 handle-resolved path into a standard filesystem path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HandlePath
    )

    $normalizedPath = $HandlePath
    if ($normalizedPath.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedPath = '\' + $normalizedPath.Substring(7)
    }
    elseif ($normalizedPath.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedPath = $normalizedPath.Substring(4)
    }

    return Normalize-CanonicalPath -Path $normalizedPath
}

function Get-ValidatedHandlePath {
    <#
    .SYNOPSIS
    Resolves the final filesystem path bound to an open file handle.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream
    )

    Initialize-HandlePathInterop

    $builder = New-Object System.Text.StringBuilder 1024
    $result = [FactoryHandlePathInterop]::GetFinalPathNameByHandle(
        $Stream.SafeFileHandle,
        $builder,
        [uint32]$builder.Capacity,
        [uint32]0)

    if ($result -eq 0) {
        $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Failed to resolve handle-bound path. Win32 error: $win32Error"
    }

    return Convert-HandlePathToCanonicalPath -HandlePath $builder.ToString()
}

function Assert-HandlePath {
    <#
    .SYNOPSIS
    Verifies that an open handle is bound to the expected canonical path.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPath,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $actualPath = Get-ValidatedHandlePath -Stream $Stream
    $expectedCanonicalPath = Normalize-CanonicalPath -Path $ExpectedPath
    if (-not $actualPath.Equals($expectedCanonicalPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Purpose handle validation failed. Expected '$expectedCanonicalPath' but resolved '$actualPath'."
    }
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

function Resolve-TaskPath {
    <#
    .SYNOPSIS
    Resolves and validates a task path inside the tracked task directory.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $candidatePath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path -Path (Get-TaskDirectory) -ChildPath $Path
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

function Get-TaskRecoveryBackupPath {
    <#
    .SYNOPSIS
    Returns the synchronized last-known-good path for a task file.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskFilePath
    )

    $taskFileCanonicalPath = Normalize-CanonicalPath -Path $TaskFilePath
    Assert-TaskPathInScope -Path $taskFileCanonicalPath

    $directoryPath = Split-Path -Parent $taskFileCanonicalPath
    $fileName = Split-Path -Leaf $taskFileCanonicalPath
    $backupPath = Join-Path -Path $directoryPath -ChildPath ('.{0}.last-known-good.json' -f $fileName)
    $backupCanonicalPath = Normalize-CanonicalPath -Path $backupPath
    Assert-TaskPathInScope -Path $backupCanonicalPath

    if ((Split-Path -Leaf $backupCanonicalPath) -notmatch '^\..+\.last-known-good\.json$') {
        throw "Backup guard rejected unexpected recovery filename: $backupCanonicalPath"
    }

    return $backupCanonicalPath
}

function Open-ValidatedFileStream {
    <#
    .SYNOPSIS
    Opens a file stream and validates that the handle resolves to the requested path.
    #>
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.IO.FileMode]$Mode,

        [Parameter(Mandatory = $true)]
        [System.IO.FileAccess]$Access,

        [Parameter(Mandatory = $true)]
        [System.IO.FileShare]$Share,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $stream = [System.IO.File]::Open($Path, $Mode, $Access, $Share)
    try {
        Assert-HandlePath -Stream $stream -ExpectedPath $Path -Purpose $Purpose
        return $stream
    }
    catch {
        $stream.Dispose()
        throw
    }
}

function Read-ValidatedTextFile {
    <#
    .SYNOPSIS
    Reads file content through a validated file handle.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $stream = $null
    $reader = $null
    try {
        $stream = Open-ValidatedFileStream -Path $Path -Mode ([System.IO.FileMode]::Open) -Access ([System.IO.FileAccess]::Read) -Share ([System.IO.FileShare]::Read) -Purpose $Purpose
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true, 1024, $false)
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
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

        return $items.ToArray()
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

function Convert-TaskJsonContentToHashtable {
    <#
    .SYNOPSIS
    Parses JSON content into a hashtable.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$ContentPath
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "JSON file is empty: $ContentPath"
    }

    try {
        return [hashtable](ConvertTo-HashtableObject -Value ($Content | ConvertFrom-Json -ErrorAction Stop))
    }
    catch {
        throw "Failed to parse JSON file '$ContentPath': $($_.Exception.Message)"
    }
}

function Read-JsonHashtable {
    <#
    .SYNOPSIS
    Reads a task JSON file and falls back to the synchronized backup when needed.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $content = Read-ValidatedTextFile -Path $Path -Purpose 'Primary task read'
        return Convert-TaskJsonContentToHashtable -Content $content -ContentPath $Path
    }
    catch {
        $backupPath = Get-TaskRecoveryBackupPath -TaskFilePath $Path
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw
        }

        Write-Warning "Primary task JSON is invalid. Falling back to synchronized backup: $backupPath"
        $backupContent = Read-ValidatedTextFile -Path $backupPath -Purpose 'Recovery backup read'
        return Convert-TaskJsonContentToHashtable -Content $backupContent -ContentPath $backupPath
    }
}

function Get-ValueByAlias {
    <#
    .SYNOPSIS
    Returns the first populated value found for the provided field aliases.
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Record,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Record.ContainsKey($name)) {
            return $Record[$name]
        }
    }

    return $null
}

function ConvertTo-ArrayLiteral {
    <#
    .SYNOPSIS
    Wraps a value in an array without enumerating single structured objects away.
    #>
    [OutputType([object[]])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ,@()
    }

    return ,@($Value)
}

function Split-CompactStringList {
    <#
    .SYNOPSIS
    Splits legacy compact comma-joined list strings into individual entries.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $trimmedValue = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
        return ,@()
    }

    if ($trimmedValue -notmatch '\S,\S') {
        return ,@($trimmedValue)
    }

    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($segment in ($trimmedValue -split '\s*,\s*')) {
        if (-not [string]::IsNullOrWhiteSpace($segment)) {
            [void]$segments.Add($segment.Trim())
        }
    }

    if ($segments.Count -lt 2) {
        return ,@($trimmedValue)
    }

    return ,($segments.ToArray())
}

function ConvertTo-StringArray {
    <#
    .SYNOPSIS
    Normalizes scalar or array values into a clean string array.
    #>
    [OutputType([string[]])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value -or $Value -is [System.Collections.IDictionary]) {
        return ,@()
    }

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($item in (ConvertTo-ArrayLiteral -Value $Value)) {
        if ($null -eq $item -or $item -is [System.Collections.IDictionary]) {
            continue
        }

        if ($item -is [string]) {
            foreach ($segment in (Split-CompactStringList -Value $item)) {
                if (-not [string]::IsNullOrWhiteSpace($segment)) {
                    [void]$items.Add($segment)
                }
            }

            continue
        }

        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            [void]$items.Add($text.Trim())
        }
    }

    return ,($items.ToArray())
}

function Get-NormalizedVerdictValue {
    <#
    .SYNOPSIS
    Returns a canonical verdict string from either a string or a structured object.
    #>
    [OutputType([string])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('status') -and $Value['status'] -is [string]) {
            return [string]$Value['status']
        }

        return ''
    }

    return [string]$Value
}

function ConvertTo-NormalizedEventList {
    <#
    .SYNOPSIS
    Normalizes event-like lists into a consistent array of hashtables.
    #>
    [OutputType([object[]])]
    param(
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [string]$DefaultType
    )

    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($item in (ConvertTo-ArrayLiteral -Value $Value)) {
        if ($item -is [System.Collections.IDictionary]) {
            $record = [hashtable]$item
            $summary = [string](Get-ValueByAlias -Record $record -Names @('summary', 'message', 'description', 'text'))
            [void]$normalized.Add([ordered]@{
                    timestamp = [string](Get-ValueByAlias -Record $record -Names @('timestamp', 'time', 'created_at', 'createdAt'))
                    type = if ([string]::IsNullOrWhiteSpace([string](Get-ValueByAlias -Record $record -Names @('type', 'kind')))) { $DefaultType } else { [string](Get-ValueByAlias -Record $record -Names @('type', 'kind')) }
                    role = [string](Get-ValueByAlias -Record $record -Names @('role', 'agent', 'actor'))
                    summary = $(if ([string]::IsNullOrWhiteSpace($summary)) { [string](Get-ValueByAlias -Record $record -Names @('detail')) } else { $summary })
                    message = if ([string]::IsNullOrWhiteSpace([string](Get-ValueByAlias -Record $record -Names @('message', 'summary', 'description', 'text')))) { [string](Get-ValueByAlias -Record $record -Names @('detail')) } else { [string](Get-ValueByAlias -Record $record -Names @('message', 'summary', 'description', 'text')) }
                })
        }
        elseif ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            [void]$normalized.Add([ordered]@{
                    timestamp = ''
                    type = $DefaultType
                    role = ''
                    summary = [string]$item
                    message = [string]$item
                })
        }
    }

    return ,($normalized.ToArray())
}

function ConvertTo-NormalizedModelAttempts {
    <#
    .SYNOPSIS
    Normalizes model-attempt entries into a consistent array of hashtables.
    #>
    [OutputType([object[]])]
    param(
        [AllowNull()]
        $Value
    )

    $normalized = New-Object System.Collections.Generic.List[object]
    foreach ($item in (ConvertTo-ArrayLiteral -Value $Value)) {
        if ($item -is [System.Collections.IDictionary]) {
            $record = [hashtable]$item
            $fallbackValue = Get-ValueByAlias -Record $record -Names @('fallback_used', 'fallbackUsed', 'used_fallback', 'usedFallback')
            [void]$normalized.Add([ordered]@{
                    timestamp = [string](Get-ValueByAlias -Record $record -Names @('timestamp', 'time', 'created_at', 'createdAt'))
                    role = [string](Get-ValueByAlias -Record $record -Names @('role', 'agent'))
                    model = [string](Get-ValueByAlias -Record $record -Names @('model', 'name'))
                    outcome = [string](Get-ValueByAlias -Record $record -Names @('outcome', 'status', 'result'))
                    fallback_used = if ($null -eq $fallbackValue) { $false } else { [bool]$fallbackValue }
                })
        }
        elseif ($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item)) {
            [void]$normalized.Add([ordered]@{
                    timestamp = ''
                    role = ''
                    model = [string]$item
                    outcome = ''
                    fallback_used = $false
                })
        }
    }

    return ,($normalized.ToArray())
}

function ConvertTo-NormalizedQaVerification {
    <#
    .SYNOPSIS
    Normalizes structured QA verification evidence into a consistent object.
    #>
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        $Value
    )

    $normalized = [ordered]@{
        present = $false
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

    if ($Value -isnot [System.Collections.IDictionary]) {
        return $normalized
    }

    $record = [hashtable]$Value
    $normalized.present = $true
    $normalized.status = if ([string]::IsNullOrWhiteSpace([string](Get-ValueByAlias -Record $record -Names @('status')))) { 'pending' } else { [string](Get-ValueByAlias -Record $record -Names @('status')) }
    $normalized.verdict_reason = [string](Get-ValueByAlias -Record $record -Names @('verdict_reason', 'verdictReason', 'reason'))
    $normalized.verifier_role = [string](Get-ValueByAlias -Record $record -Names @('verifier_role', 'verifierRole', 'role'))
    $normalized.invocation_path = [string](Get-ValueByAlias -Record $record -Names @('invocation_path', 'invocationPath'))
    $normalized.execution_mode = [string](Get-ValueByAlias -Record $record -Names @('execution_mode', 'executionMode'))
    $normalized.evidence_sufficiency = if ([string]::IsNullOrWhiteSpace([string](Get-ValueByAlias -Record $record -Names @('evidence_sufficiency', 'evidenceSufficiency')))) { 'insufficient' } else { [string](Get-ValueByAlias -Record $record -Names @('evidence_sufficiency', 'evidenceSufficiency')) }
    $normalized.blocking_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('blocking_checks', 'blockingChecks', 'required_checks', 'requiredChecks'))
    $normalized.advisory_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('advisory_checks', 'advisoryChecks', 'optional_checks', 'optionalChecks'))
    $normalized.passed_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('passed_checks', 'passedChecks'))
    $normalized.failed_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('failed_checks', 'failedChecks', 'blocking_findings', 'blockingFindings'))
    $normalized.skipped_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('skipped_checks', 'skippedChecks'))
    $normalized.not_possible_checks = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('not_possible_checks', 'notPossibleChecks'))
    $normalized.commands = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('commands', 'executed_commands', 'executedCommands'))
    $normalized.artifacts = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('artifacts', 'evidence_artifacts', 'evidenceArtifacts'))
    $normalized.limitations = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $record -Names @('limitations', 'remaining_gaps', 'remainingGaps', 'gaps'))

    return $normalized
}

function Get-QaQualityGate {
    <#
    .SYNOPSIS
    Derives an operator-facing QA quality classification.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$QaStatus,

        [Parameter(Mandatory = $true)]
        [hashtable]$QaVerification
    )

    if ($QaStatus -eq 'fail') {
        return 'fail'
    }

    if ($QaStatus -eq 'pending') {
        return 'pending'
    }

    if (-not $QaVerification.present) {
        return 'legacy_unstructured_pass'
    }

    if ($QaVerification.status -ne 'pass') {
        return 'insufficient_evidence'
    }

    if ($QaVerification.evidence_sufficiency -ne 'sufficient') {
        return 'insufficient_evidence'
    }

    if (@($QaVerification.blocking_checks).Count -eq 0) {
        return 'insufficient_evidence'
    }

    if (@($QaVerification.failed_checks).Count -gt 0) {
        return 'insufficient_evidence'
    }

    if ((@($QaVerification.commands).Count + @($QaVerification.artifacts).Count) -eq 0) {
        return 'insufficient_evidence'
    }

    foreach ($blockingCheck in @($QaVerification.blocking_checks)) {
        if ($QaVerification.passed_checks -notcontains $blockingCheck) {
            return 'insufficient_evidence'
        }

        if ($QaVerification.skipped_checks -contains $blockingCheck) {
            return 'insufficient_evidence'
        }

        if ($QaVerification.not_possible_checks -contains $blockingCheck) {
            return 'insufficient_evidence'
        }
    }

    return 'strict_pass'
}

function Normalize-TaskRecord {
    <#
    .SYNOPSIS
    Normalizes a task record across known schema variations.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Record,

        [Parameter(Mandatory = $true)]
        [string]$TaskPath
    )

    $status = [string](Get-ValueByAlias -Record $Record -Names @('status', 'state'))
    $phase = [string](Get-ValueByAlias -Record $Record -Names @('current_phase', 'currentPhase', 'phase'))
    $blockerValue = Get-ValueByAlias -Record $Record -Names @('blocker', 'blocking_reason', 'blockingReason', 'blockers')
    $blockers = ConvertTo-StringArray -Value $blockerValue
    $events = ConvertTo-NormalizedEventList -Value (Get-ValueByAlias -Record $Record -Names @('events', 'event_log', 'eventLog')) -DefaultType 'task_event'
    $executionLog = ConvertTo-NormalizedEventList -Value (Get-ValueByAlias -Record $Record -Names @('execution_log', 'executionLog', 'log', 'activity_log')) -DefaultType 'execution_log'
    $modelAttempts = ConvertTo-NormalizedModelAttempts -Value (Get-ValueByAlias -Record $Record -Names @('model_attempts', 'modelAttempts', 'model_history', 'modelHistory'))
    $reviewStatus = Get-NormalizedVerdictValue -Value (Get-ValueByAlias -Record $Record -Names @('review_result', 'reviewStatus', 'review_status', 'review'))
    $securityStatus = Get-NormalizedVerdictValue -Value (Get-ValueByAlias -Record $Record -Names @('security_result', 'securityStatus', 'security_status', 'security'))
    $qaStatus = Get-NormalizedVerdictValue -Value (Get-ValueByAlias -Record $Record -Names @('qa_result', 'qaStatus', 'qa_status', 'qa', 'test_result'))
    $qaVerification = ConvertTo-NormalizedQaVerification -Value (Get-ValueByAlias -Record $Record -Names @('qa_verification', 'qaVerification'))
    $qaQualityGate = Get-QaQualityGate -QaStatus $qaStatus -QaVerification $qaVerification
    $approvalRequired = $status -eq 'awaiting_human_approval' -or $phase -eq 'human_approval'
    $completedGateChecks = @($reviewStatus, $securityStatus, $qaStatus | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $gateStatus = if (@($reviewStatus, $securityStatus, $qaStatus) -contains 'fail') {
        'failed'
    }
    elseif ($approvalRequired) {
        'awaiting_human_approval'
    }
    elseif (@($reviewStatus, $securityStatus, $qaStatus) -contains 'pending') {
        'pending_checks'
    }
    elseif ($completedGateChecks.Count -gt 0) {
        'passed'
    }
    else {
        'not_started'
    }

    $latestEvent = if (@($events).Count -gt 0) { @($events)[-1] } elseif (@($executionLog).Count -gt 0) { @($executionLog)[-1] } else { $null }
    $latestModelAttempt = if (@($modelAttempts).Count -gt 0) { @($modelAttempts)[-1] } else { $null }
    $derivedRole = [string](Get-ValueByAlias -Record $Record -Names @('current_role', 'currentRole', 'role'))
    $derivedModel = [string](Get-ValueByAlias -Record $Record -Names @('current_model', 'currentModel', 'model'))
    $fallbackUsedValue = Get-ValueByAlias -Record $Record -Names @('fallback_used', 'fallbackUsed', 'used_fallback', 'usedFallback')

    return [ordered]@{
        task_path = $TaskPath
        schema_version = [string](Get-ValueByAlias -Record $Record -Names @('schema_version', 'schemaVersion', 'version'))
        state_backend = [string](Get-ValueByAlias -Record $Record -Names @('state_backend', 'stateBackend'))
        task_id = [string](Get-ValueByAlias -Record $Record -Names @('task_id', 'taskId', 'id'))
        objective = [string](Get-ValueByAlias -Record $Record -Names @('objective', 'title', 'summary'))
        scope = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $Record -Names @('scope', 'scopes'))
        constraints = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $Record -Names @('constraints', 'guardrails'))
        priority = [string](Get-ValueByAlias -Record $Record -Names @('priority', 'severity'))
        current_phase = $phase
        current_role = $derivedRole
        current_model = $derivedModel
        fallback_used = if ($null -eq $fallbackUsedValue) { $false } else { [bool]$fallbackUsedValue }
        status = $status
        created_at = [string](Get-ValueByAlias -Record $Record -Names @('created_at', 'createdAt'))
        updated_at = [string](Get-ValueByAlias -Record $Record -Names @('updated_at', 'updatedAt', 'last_updated', 'lastUpdated', 'modified_at'))
        findings = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $Record -Names @('findings', 'notes'))
        remaining_work = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $Record -Names @('remaining_work', 'remainingWork', 'next_steps', 'remaining'))
        evidence = ConvertTo-StringArray -Value (Get-ValueByAlias -Record $Record -Names @('evidence', 'artifacts', 'links'))
        review_result = if ([string]::IsNullOrWhiteSpace($reviewStatus)) { 'pending' } else { $reviewStatus }
        security_result = if ([string]::IsNullOrWhiteSpace($securityStatus)) { 'pending' } else { $securityStatus }
        qa_result = if ([string]::IsNullOrWhiteSpace($qaStatus)) { 'pending' } else { $qaStatus }
        qa_verification = $qaVerification
        qa_verification_present = [bool]$qaVerification.present
        qa_evidence_sufficiency = [string]$qaVerification.evidence_sufficiency
        qa_invocation_path = [string]$qaVerification.invocation_path
        qa_execution_mode = [string]$qaVerification.execution_mode
        qa_blocking_check_count = @($qaVerification.blocking_checks).Count
        qa_advisory_check_count = @($qaVerification.advisory_checks).Count
        qa_passed_check_count = @($qaVerification.passed_checks).Count
        qa_failed_check_count = @($qaVerification.failed_checks).Count
        qa_skipped_check_count = @($qaVerification.skipped_checks).Count
        qa_not_possible_check_count = @($qaVerification.not_possible_checks).Count
        qa_command_count = @($qaVerification.commands).Count
        qa_artifact_count = @($qaVerification.artifacts).Count
        qa_quality_gate = $qaQualityGate
        retry_count = [int](Get-ValueByAlias -Record $Record -Names @('retry_count', 'retryCount', 'retries'))
        blocker = if (@($blockers).Count -gt 0) { $blockers -join '; ' } else { '' }
        blocker_state = if ($status -eq 'blocked' -or @($blockers).Count -gt 0) { 'blocked' } else { 'clear' }
        next_automatic_action = [string](Get-ValueByAlias -Record $Record -Names @('next_automatic_action', 'nextAutomaticAction', 'next_step', 'nextStep'))
        escalation_reason = [string](Get-ValueByAlias -Record $Record -Names @('escalation_reason', 'escalationReason'))
        verification_summary = [string](Get-ValueByAlias -Record $Record -Names @('verification_summary', 'verificationSummary', 'verification'))
        final_outcome = [string](Get-ValueByAlias -Record $Record -Names @('final_outcome', 'finalOutcome', 'outcome'))
        execution_log = $executionLog
        events = $events
        latest_event = $latestEvent
        model_attempts = $modelAttempts
        latest_model_attempt = $latestModelAttempt
        model_attempt_count = @($modelAttempts).Count
        capability_classification = Get-ValueByAlias -Record $Record -Names @('capability_classification', 'capabilityClassification')
        approval_required = $approvalRequired
        gate_status = $gateStatus
    }
}

function Write-TextSummary {
    <#
    .SYNOPSIS
    Writes a concise human-readable summary.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )

    $latestEventSummary = if ($null -ne $Summary.latest_event) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Summary.latest_event.summary)) {
            [string]$Summary.latest_event.summary
        }
        else {
            [string]$Summary.latest_event.message
        }
    }
    else {
        'none'
    }

    $latestModelSummary = if ($null -ne $Summary.latest_model_attempt) {
        "{0} ({1})" -f $Summary.latest_model_attempt.model, $Summary.latest_model_attempt.outcome
    }
    else {
        'none'
    }

    Write-Host "Task ID: $($Summary.task_id)"
    Write-Host "Objective: $($Summary.objective)"
    Write-Host "Status: $($Summary.status)"
    Write-Host "Current phase: $($Summary.current_phase)"
    Write-Host "Current role: $($Summary.current_role)"
    Write-Host "Current model: $($Summary.current_model)"
    Write-Host "Fallback used: $($Summary.fallback_used)"
    Write-Host "Approval required: $($Summary.approval_required)"
    Write-Host "Gate status: $($Summary.gate_status)"
    Write-Host "Review/Security/QA: $($Summary.review_result) / $($Summary.security_result) / $($Summary.qa_result)"
    Write-Host "QA quality gate: $($Summary.qa_quality_gate)"
    Write-Host "QA verification present: $($Summary.qa_verification_present)"
    Write-Host "QA evidence sufficiency: $($Summary.qa_evidence_sufficiency)"
    Write-Host "QA path/mode: $($Summary.qa_invocation_path) / $($Summary.qa_execution_mode)"
    Write-Host "QA checks blocking/passed/failed/skipped/not-possible: $($Summary.qa_blocking_check_count) / $($Summary.qa_passed_check_count) / $($Summary.qa_failed_check_count) / $($Summary.qa_skipped_check_count) / $($Summary.qa_not_possible_check_count)"
    Write-Host "QA evidence commands/artifacts: $($Summary.qa_command_count) / $($Summary.qa_artifact_count)"
    Write-Host "Latest event: $latestEventSummary"
    Write-Host "Latest model attempt: $latestModelSummary"
    Write-Host "Model attempt count: $($Summary.model_attempt_count)"
    Write-Host "Blocker state: $($Summary.blocker_state)"
    Write-Host "Blocker: $($Summary.blocker)"
    Write-Host "Next automatic action: $($Summary.next_automatic_action)"
    Write-Host "Task file: $($Summary.task_path)"
}

function Main {
    <#
    .SYNOPSIS
    Produces a normalized summary for the requested task file.
    #>
    [OutputType([void])]
    param()

    $resolvedTaskPath = Resolve-TaskPath -Path $TaskPath
    $taskRecord = Read-JsonHashtable -Path $resolvedTaskPath
    $summary = Normalize-TaskRecord -Record $taskRecord -TaskPath $resolvedTaskPath

    if ($AsJson.IsPresent) {
        Write-Output ($summary | ConvertTo-Json -Depth 20)
        return
    }

    Write-TextSummary -Summary $summary
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
