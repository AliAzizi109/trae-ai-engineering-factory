<#
.SYNOPSIS
Updates a Factory V2 task-state JSON record safely.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath,

    [Parameter()]
    [ValidateSet('low', 'medium', 'high', 'critical')]
    [string]$Priority,

    [Parameter()]
    [ValidateSet('intake', 'discovery', 'research', 'plan', 'implement', 'review', 'security_review', 'qa', 'release_gate', 'human_approval')]
    [string]$CurrentPhase,

    [Parameter()]
    [ValidateSet('chief_orchestrator', 'planner_architect', 'research_docs', 'coder_implementer', 'code_reviewer', 'security_reviewer', 'qa_test_verifier', 'git_release_gatekeeper', 'task_state_coordinator', 'lightweight_routine')]
    [string]$CurrentRole,

    [Parameter()]
    [string]$CurrentModel,

    [Parameter()]
    [Nullable[bool]]$FallbackUsed,

    [Parameter()]
    [ValidateSet('open', 'in_progress', 'blocked', 'awaiting_human_approval', 'completed')]
    [string]$Status,

    [Parameter()]
    [Nullable[int]]$RetryCount,

    [Parameter()]
    [string]$Blocker,

    [Parameter()]
    [string]$NextAutomaticAction,

    [Parameter()]
    [string]$EscalationReason,

    [Parameter()]
    [string]$FinalOutcome,

    [Parameter()]
    [string]$CapabilityClassification,

    [Parameter()]
    [ValidateSet('pending', 'pass', 'fail')]
    [string]$ReviewStatus,

    [Parameter()]
    [ValidateSet('pending', 'pass', 'fail')]
    [string]$SecurityStatus,

    [Parameter()]
    [ValidateSet('pending', 'pass', 'fail')]
    [string]$QaStatus,

    [Parameter()]
    [string[]]$AppendFinding = @(),

    [Parameter()]
    [string[]]$AppendVerificationSummary = @(),

    [Parameter()]
    [string[]]$AppendExecutionLog = @(),

    [Parameter()]
    [string[]]$AppendEvent = @(),

    [Parameter()]
    [string[]]$AppendModelAttempt = @(),

    [Parameter()]
    [string[]]$AppendArtifact = @(),

    [Parameter()]
    [string[]]$AppendScope = @(),

    [Parameter()]
    [string[]]$AppendConstraint = @(),

    [Parameter()]
    [string[]]$AppendRemainingWork = @(),

    [Parameter()]
    [string[]]$AppendEvidence = @(),

    [Parameter()]
    [string[]]$AppendEventJson = @(),

    [Parameter()]
    [string[]]$AppendModelAttemptJson = @(),

    [Parameter()]
    [string]$SetFieldJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AllowedTaskPriorities = @('low', 'medium', 'high', 'critical')

function Get-ProjectRoot {
    [OutputType([string])]
    param()

    return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function Read-TaskState {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Stream')]
        [System.IO.Stream]$Stream,

        [Parameter(ParameterSetName = 'Stream')]
        [string]$DisplayPath = '<stream>',

        [Parameter()]
        [ref]$ResolvedContent = ([ref]$null)
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $contentPath = $Path
        $content = Get-TaskJsonContent -Path $Path
    }
    else {
        $contentPath = $DisplayPath
        $content = Get-TaskJsonContent -Stream $Stream
    }

    try {
        $state = Convert-TaskJsonContentToState -Content $content -ContentPath $contentPath
        if ($null -ne $ResolvedContent) {
            $ResolvedContent.Value = $content
        }
        return $state
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($contentPath) -or $contentPath -eq '<stream>') {
            throw
        }

        $backupPath = Get-TaskRecoveryBackupPath -TaskFilePath $contentPath
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw
        }

        Assert-DirectTaskFile -Path $backupPath
        Assert-NoReparsePointsInPath -RootPath (Get-FactoryTasksRoot -ProjectRoot (Get-ProjectRoot)) -TargetPath $backupPath
        $backupContent = Get-TaskJsonContent -Path $backupPath
        $state = Convert-TaskJsonContentToState -Content $backupContent -ContentPath $backupPath
        if ($null -ne $ResolvedContent) {
            $ResolvedContent.Value = $backupContent
        }
        return $state
    }
}

function ConvertTo-HashtableObject {
    [OutputType([object])]
    param(
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $table = @{}
        foreach ($key in $Value.Keys) {
            $table[$key] = ConvertTo-HashtableObject -Value $Value[$key]
        }
        return $table
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((ConvertTo-HashtableObject -Value $item))
        }
        return ,($items.ToArray())
    }

    if ($null -ne $Value.PSObject -and @($Value.PSObject.Properties).Count -gt 0 -and $Value -isnot [string]) {
        $table = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-HashtableObject -Value $property.Value
        }
        return $table
    }

    return $Value
}

function Convert-HashBytesToHexString {
    <#
    .SYNOPSIS
    Converts hash bytes to a lowercase hexadecimal string.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$HashBytes
    )

    return ([System.BitConverter]::ToString($HashBytes)).Replace('-', '').ToLowerInvariant()
}

function Get-ContentFingerprintSha256FromStream {
    <#
    .SYNOPSIS
    Computes a SHA-256 fingerprint from a readable stream while preserving position.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream
    )

    if (-not $Stream.CanRead) {
        throw 'Cannot compute a SHA-256 fingerprint from a non-readable stream.'
    }

    [bool]$restorePosition = $Stream.CanSeek
    [long]$originalPosition = 0
    if ($restorePosition) {
        $originalPosition = $Stream.Position
        $Stream.Position = 0
    }

    $sha256 = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($Stream)
        return Convert-HashBytesToHexString -HashBytes $hashBytes
    }
    catch {
        throw "Failed to compute task file SHA-256 fingerprint from stream: $($_.Exception.Message)"
    }
    finally {
        if ($restorePosition) {
            $Stream.Position = $originalPosition
        }

        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
    }
}

function Get-ContentFingerprintSha256FromPath {
    <#
    .SYNOPSIS
    Computes a SHA-256 fingerprint from a filesystem path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read)
    }
    catch {
        throw "Failed to open task file for SHA-256 fingerprint read '$Path': $($_.Exception.Message)"
    }

    try {
        return Get-ContentFingerprintSha256FromStream -Stream $stream
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-TaskRecoveryBackupPath {
    <#
    .SYNOPSIS
    Returns the deterministic recovery backup path for a task JSON file.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskFilePath
    )

    $directoryPath = Split-Path -Parent $TaskFilePath
    $fileName = Split-Path -Leaf $TaskFilePath
    return Join-Path -Path $directoryPath -ChildPath ('.{0}.last-known-good.json' -f $fileName)
}

function Get-TaskJsonContent {
    <#
    .SYNOPSIS
    Reads raw task JSON text from a path or stream.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'Stream')]
        [System.IO.Stream]$Stream
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        return Get-Content -LiteralPath $Path -Raw
    }

    if ($Stream.CanSeek) {
        $Stream.Position = 0
    }

    $reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }
}

function Convert-TaskJsonContentToState {
    <#
    .SYNOPSIS
    Parses raw task JSON content into a state hashtable.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$ContentPath
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        throw "Task JSON is empty: $ContentPath"
    }

    try {
        return ConvertTo-HashtableObject -Value ($Content | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse task JSON '$ContentPath': $($_.Exception.Message)"
    }
}

function Write-TaskState {
    <#
    .SYNOPSIS
    Writes task state JSON through the validated task file handle.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$TaskFilePath,

        [Parameter(Mandatory = $true)]
        [string]$TasksRoot,

        [Parameter(Mandatory = $true)]
        [string]$PreviousContent
    )

    $content = $State | ConvertTo-Json -Depth 10
    $contentWithNewline = $content + [Environment]::NewLine
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $backupPath = Get-TaskRecoveryBackupPath -TaskFilePath $TaskFilePath
    $backupStream = $null

    try {
        if (-not (Test-PathWithinRoot -RootPath $TasksRoot -CandidatePath $backupPath)) {
            throw "Task recovery backup path must stay inside the Factory tasks directory: $TasksRoot"
        }

        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Assert-DirectTaskFile -Path $backupPath
            Assert-NoReparsePointsInPath -RootPath $TasksRoot -TargetPath $backupPath
            $backupStream = [System.IO.File]::Open(
                $backupPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
        }
        else {
            $backupStream = [System.IO.File]::Open(
                $backupPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
        }

        $backupBytes = $utf8NoBom.GetBytes($PreviousContent)
        $backupStream.Position = 0
        $backupStream.Write($backupBytes, 0, $backupBytes.Length)
        $backupStream.SetLength($backupBytes.Length)
        $backupStream.Flush($true)
    }
    catch {
        throw "Failed to persist task recovery backup '$backupPath': $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $backupStream) {
            $backupStream.Dispose()
        }
    }

    try {
        Assert-OpenedTaskFileWithinRoot -RootPath $TasksRoot -Stream $Stream
        $contentBytes = $utf8NoBom.GetBytes($contentWithNewline)
        $Stream.Position = 0
        $Stream.Write($contentBytes, 0, $contentBytes.Length)
        $Stream.SetLength($contentBytes.Length)
        $Stream.Flush($true)
    }
    catch {
        throw "Failed to write task JSON through the validated task handle '$TaskFilePath': $($_.Exception.Message)"
    }

    try {
        Assert-DirectTaskFile -Path $backupPath
        Assert-NoReparsePointsInPath -RootPath $TasksRoot -TargetPath $backupPath
        $backupStream = Open-ValidatedTaskFileForUpdate -Path $backupPath -TasksRoot $TasksRoot
        Assert-ResolvedTaskPathMatchesOpenedTaskFile -Path $backupPath -Stream $backupStream
        $currentBackupBytes = $utf8NoBom.GetBytes($contentWithNewline)
        $backupStream.Position = 0
        $backupStream.Write($currentBackupBytes, 0, $currentBackupBytes.Length)
        $backupStream.SetLength($currentBackupBytes.Length)
        $backupStream.Flush($true)
    }
    catch {
        throw "Failed to refresh task recovery backup '$backupPath' after successful write: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $backupStream) {
            $backupStream.Dispose()
        }
    }
}

function Test-HasMaterialLinkTarget {
    <#
    .SYNOPSIS
    Determines whether a link target value contains a real non-empty target.
    #>
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object]$Target
    )

    if ($null -eq $Target) {
        return $false
    }

    if ($Target -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Target)
    }

    if ($Target -is [System.Collections.IEnumerable]) {
        foreach ($item in $Target) {
            if (Test-HasMaterialLinkTarget -Target $item) {
                return $true
            }
        }

        return $false
    }

    return -not [string]::IsNullOrWhiteSpace([string]$Target)
}

function Read-JsonHashtable {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description was not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "$Description is empty: $Path"
    }

    try {
        return ConvertTo-HashtableObject -Value ($content | ConvertFrom-Json)
    }
    catch {
        throw "Failed to parse $Description '$Path': $($_.Exception.Message)"
    }
}

function Get-TaskStateContract {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $handoffsPath = Join-Path -Path $ProjectRoot -ChildPath '.trae\factory\config\handoffs.json'
    $roleSystemPath = Join-Path -Path $ProjectRoot -ChildPath '.trae\factory\config\role-system.json'
    $handoffs = Read-JsonHashtable -Path $handoffsPath -Description 'Factory handoff contract'
    $roleSystem = Read-JsonHashtable -Path $roleSystemPath -Description 'Factory role contract'

    $phases = @($handoffs.phase_sequence | ForEach-Object { [string]$_ })
    $roles = @($roleSystem.roles.Keys | ForEach-Object { [string]$_ })

    if ($phases.Count -eq 0) {
        throw "Factory handoff contract does not define any phases: $handoffsPath"
    }

    if ($roles.Count -eq 0) {
        throw "Factory role contract does not define any roles: $roleSystemPath"
    }

    return @{
        priority = $script:AllowedTaskPriorities
        current_phase = $phases
        current_role = $roles
        status = @('open', 'in_progress', 'blocked', 'awaiting_human_approval', 'completed')
        verdict = @('pending', 'pass', 'fail')
    }
}

function Assert-AllowedStringValue {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedValues
    )

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Field '$FieldName' must be a non-empty string."
    }

    if ($AllowedValues -notcontains $Value) {
        throw "Field '$FieldName' has invalid value '$Value'. Allowed values: $($AllowedValues -join ', ')"
    }
}

function Assert-StringFieldValue {
    <#
    .SYNOPSIS
    Validates that a task-state field is a string value.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -isnot [string]) {
        throw "Field '$FieldName' must be a string."
    }
}

function Assert-BooleanFieldValue {
    <#
    .SYNOPSIS
    Validates that a task-state field is a boolean value.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -isnot [bool]) {
        throw "Field '$FieldName' must be a boolean."
    }
}

function Test-IsIntegerValue {
    <#
    .SYNOPSIS
    Determines whether a value is backed by an integer numeric type.
    #>
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    return (
        ($Value -is [byte]) -or
        ($Value -is [sbyte]) -or
        ($Value -is [int16]) -or
        ($Value -is [uint16]) -or
        ($Value -is [int32]) -or
        ($Value -is [uint32]) -or
        ($Value -is [int64]) -or
        ($Value -is [uint64])
    )
}

function Assert-NonNegativeIntegerFieldValue {
    <#
    .SYNOPSIS
    Validates that a task-state field is a non-negative integer value.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if (-not (Test-IsIntegerValue -Value $Value)) {
        throw "Field '$FieldName' must be a non-negative integer."
    }

    if ([int64]$Value -lt 0) {
        throw "Field '$FieldName' must be a non-negative integer."
    }
}

function Assert-ObjectFieldValue {
    <#
    .SYNOPSIS
    Validates that a task-state field is a JSON object/dictionary.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -isnot [System.Collections.IDictionary]) {
        throw "Field '$FieldName' must be a JSON object."
    }
}

function Assert-StringArrayFieldValue {
    <#
    .SYNOPSIS
    Validates that a task-state field is an array of non-empty strings.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Field '$FieldName' must be an array of non-empty strings."
    }

    foreach ($item in @($Value)) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
            throw "Field '$FieldName' must be an array of non-empty strings."
        }
    }
}

function Assert-RequiredObjectProperty {
    <#
    .SYNOPSIS
    Validates that an object entry contains a required property.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($Entry.Keys -notcontains $PropertyName) {
        throw "Field '$EntryName' must contain property '$PropertyName'."
    }
}

function Assert-RequiredStringProperty {
    <#
    .SYNOPSIS
    Validates that an object entry contains a required non-empty string property.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    Assert-RequiredObjectProperty -EntryName $EntryName -Entry $Entry -PropertyName $PropertyName

    if ($Entry[$PropertyName] -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Entry[$PropertyName])) {
        throw "Field '$EntryName.$PropertyName' must be a non-empty string."
    }
}

function Assert-RequiredBooleanProperty {
    <#
    .SYNOPSIS
    Validates that an object entry contains a required boolean property.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EntryName,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Entry,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    Assert-RequiredObjectProperty -EntryName $EntryName -Entry $Entry -PropertyName $PropertyName
    Assert-BooleanFieldValue -FieldName "$EntryName.$PropertyName" -Value $Entry[$PropertyName]
}

function Assert-ExecutionLogFieldValue {
    <#
    .SYNOPSIS
    Validates execution_log entries against the baseline task-state schema.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Field '$FieldName' must be an array of execution log objects."
    }

    $index = 0
    foreach ($entry in @($Value)) {
        $entryName = "${FieldName}[$index]"
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "Field '$entryName' must be an object."
        }

        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'timestamp'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'role'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'message'
        $index++
    }
}

function Assert-EventsFieldValue {
    <#
    .SYNOPSIS
    Validates event entries against the baseline task-state schema.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Field '$FieldName' must be an array of event objects."
    }

    $index = 0
    foreach ($entry in @($Value)) {
        $entryName = "${FieldName}[$index]"
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "Field '$entryName' must be an object."
        }

        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'timestamp'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'type'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'role'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'summary'
        $index++
    }
}

function Assert-ModelAttemptsFieldValue {
    <#
    .SYNOPSIS
    Validates model_attempts entries against the baseline task-state schema.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) {
        throw "Field '$FieldName' must be an array of model attempt objects."
    }

    $index = 0
    foreach ($entry in @($Value)) {
        $entryName = "${FieldName}[$index]"
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw "Field '$entryName' must be an object."
        }

        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'timestamp'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'role'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'model'
        Assert-RequiredStringProperty -EntryName $entryName -Entry $entry -PropertyName 'outcome'
        Assert-RequiredBooleanProperty -EntryName $entryName -Entry $entry -PropertyName 'fallback_used'
        $index++
    }
}

function Assert-ValidatedTaskStateFieldValue {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter()]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [hashtable]$Contract
    )

    switch ($FieldName) {
        'priority' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.priority
            break
        }
        'current_phase' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.current_phase
            break
        }
        'current_role' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.current_role
            break
        }
        'status' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.status
            break
        }
        'review_result' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.verdict
            break
        }
        'security_result' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.verdict
            break
        }
        'qa_result' {
            Assert-AllowedStringValue -FieldName $FieldName -Value $Value -AllowedValues $Contract.verdict
            break
        }
        'scope' {
            Assert-StringArrayFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'constraints' {
            Assert-StringArrayFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'findings' {
            Assert-StringArrayFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'remaining_work' {
            Assert-StringArrayFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'evidence' {
            Assert-StringArrayFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'execution_log' {
            Assert-ExecutionLogFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'events' {
            Assert-EventsFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'model_attempts' {
            Assert-ModelAttemptsFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'capability_classification' {
            Assert-ObjectFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'task_id' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'objective' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'verification_summary' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'blocker' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'next_automatic_action' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'escalation_reason' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'final_outcome' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'current_model' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'created_at' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'updated_at' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'schema_version' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'state_backend' {
            Assert-StringFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'fallback_used' {
            Assert-BooleanFieldValue -FieldName $FieldName -Value $Value
            break
        }
        'retry_count' {
            Assert-NonNegativeIntegerFieldValue -FieldName $FieldName -Value $Value
            break
        }
    }
}

function Assert-TaskStateContract {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Contract
    )

    Assert-ValidatedTaskStateFieldValue -FieldName 'priority' -Value $State.priority -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'current_phase' -Value $State.current_phase -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'current_role' -Value $State.current_role -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'status' -Value $State.status -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'review_result' -Value $State.review_result -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'security_result' -Value $State.security_result -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'qa_result' -Value $State.qa_result -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'task_id' -Value $State.task_id -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'objective' -Value $State.objective -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'scope' -Value $State.scope -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'constraints' -Value $State.constraints -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'current_model' -Value $State.current_model -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'fallback_used' -Value $State.fallback_used -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'created_at' -Value $State.created_at -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'updated_at' -Value $State.updated_at -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'findings' -Value $State.findings -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'remaining_work' -Value $State.remaining_work -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'evidence' -Value $State.evidence -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'retry_count' -Value $State.retry_count -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'blocker' -Value $State.blocker -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'next_automatic_action' -Value $State.next_automatic_action -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'escalation_reason' -Value $State.escalation_reason -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'verification_summary' -Value $State.verification_summary -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'final_outcome' -Value $State.final_outcome -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'execution_log' -Value $State.execution_log -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'events' -Value $State.events -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'model_attempts' -Value $State.model_attempts -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'capability_classification' -Value $State.capability_classification -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'schema_version' -Value $State.schema_version -Contract $Contract
    Assert-ValidatedTaskStateFieldValue -FieldName 'state_backend' -Value $State.state_backend -Contract $Contract
}

function Ensure-List {
    [OutputType([object[]])]
    param(
        [Parameter()]
        $Value
    )

    if ($null -eq $Value) {
        return ,@()
    }

    return ,@($Value)
}

function Add-StringEntries {
    [OutputType([object[]])]
    param(
        [Parameter()]
        [object[]]$Existing = @(),

        [Parameter()]
        [string[]]$Items
    )

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Existing) {
        $merged.Add($item)
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $merged.Add($item.Trim())
        }
    }

    return ,($merged.ToArray())
}

function Append-TextBlock {
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Existing,

        [Parameter()]
        [string[]]$Items
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Existing)) {
        foreach ($line in ($Existing -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $lines.Add($line)
            }
        }
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $lines.Add($item.Trim())
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Add-JsonEntries {
    [OutputType([object[]])]
    param(
        [Parameter()]
        [object[]]$Existing = @(),

        [Parameter()]
        [string[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$DestinationField
    )

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Existing) {
        $merged.Add($item)
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            try {
                $entry = ConvertTo-HashtableObject -Value ($item | ConvertFrom-Json)
            }
            catch {
                throw "Invalid $DestinationField JSON entry: $($_.Exception.Message)"
            }

            try {
                Assert-ValidatedTaskStateFieldValue -FieldName $DestinationField -Value @($entry) -Contract @{}
            }
            catch {
                throw "Invalid $DestinationField JSON entry: $($_.Exception.Message)"
            }

            $merged.Add($entry)
        }
    }

    return ,($merged.ToArray())
}

function ConvertFrom-SetFieldJson {
    <#
    .SYNOPSIS
    Parses SetFieldJson while preserving single-item array shapes.
    #>
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonText
    )

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return ($JsonText | ConvertFrom-Json -AsHashtable -NoEnumerate)
        }

        Add-Type -AssemblyName 'System.Web.Extensions' -ErrorAction Stop | Out-Null
        $serializer = [System.Web.Script.Serialization.JavaScriptSerializer]::new()
        $serializer.MaxJsonLength = [int]::MaxValue
        return ConvertTo-HashtableObject -Value ($serializer.DeserializeObject($JsonText))
    }
    catch {
        throw "SetFieldJson must be valid JSON: $($_.Exception.Message)"
    }
}

function Apply-JsonFieldUpdates {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$JsonText,

        [Parameter(Mandatory = $true)]
        [hashtable]$Contract
    )

    $allowedFields = @(
        'task_id',
        'objective',
        'scope',
        'constraints',
        'priority',
        'current_phase',
        'current_role',
        'current_model',
        'fallback_used',
        'status',
        'created_at',
        'updated_at',
        'findings',
        'remaining_work',
        'evidence',
        'review_result',
        'security_result',
        'qa_result',
        'retry_count',
        'blocker',
        'next_automatic_action',
        'escalation_reason',
        'verification_summary',
        'final_outcome',
        'execution_log',
        'events',
        'model_attempts',
        'capability_classification'
    )

    $requestedUpdates = ConvertFrom-SetFieldJson -JsonText $JsonText

    if ($requestedUpdates -isnot [System.Collections.IDictionary]) {
        throw 'SetFieldJson must be a JSON object.'
    }

    foreach ($entry in $requestedUpdates.GetEnumerator()) {
        $fieldName = [string]$entry.Key
        $fieldValue = $requestedUpdates[$fieldName]

        if ($allowedFields -notcontains $fieldName) {
            throw "Unsupported field in SetFieldJson: $fieldName"
        }

        Assert-ValidatedTaskStateFieldValue -FieldName $fieldName -Value $fieldValue -Contract $Contract
        $State[$fieldName] = $fieldValue
    }
}

function Add-EventEntries {
    [OutputType([object[]])]
    param(
        [Parameter()]
        [object[]]$Existing = @(),

        [Parameter()]
        [string[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp,

        [Parameter()]
        [string]$Role
    )

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Existing) {
        $merged.Add($item)
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $merged.Add(@{
                timestamp = $Timestamp
                type = 'note'
                role = $Role
                summary = $item.Trim()
            })
        }
    }

    return ,($merged.ToArray())
}

function Add-ExecutionLogEntries {
    [OutputType([object[]])]
    param(
        [Parameter()]
        [object[]]$Existing = @(),

        [Parameter()]
        [string[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp,

        [Parameter(Mandatory = $true)]
        [string]$Role
    )

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Existing) {
        $merged.Add($item)
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $merged.Add(@{
                timestamp = $Timestamp
                role = $Role
                message = $item.Trim()
            })
        }
    }

    return ,($merged.ToArray())
}

function Add-ModelAttemptEntries {
    [OutputType([object[]])]
    param(
        [Parameter()]
        [object[]]$Existing = @(),

        [Parameter()]
        [string[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Timestamp,

        [Parameter()]
        [string]$Role,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [Nullable[bool]]$WasFallback
    )

    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Existing) {
        $merged.Add($item)
    }

    foreach ($item in @($Items)) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $merged.Add(@{
                timestamp = $Timestamp
                role = $Role
                model = $Model
                outcome = $item.Trim()
                fallback_used = $(if ($null -eq $WasFallback) { $false } else { [bool]$WasFallback })
            })
        }
    }

    return ,($merged.ToArray())
}

function Test-HasRequestedChange {
    [OutputType([bool])]
    param()

    $scalarValues = @(
        $Priority,
        $CurrentPhase,
        $CurrentRole,
        $CurrentModel,
        $Status,
        $Blocker,
        $NextAutomaticAction,
        $EscalationReason,
        $FinalOutcome,
        $CapabilityClassification,
        $ReviewStatus,
        $SecurityStatus,
        $QaStatus,
        $SetFieldJson
    )

    foreach ($value in $scalarValues) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $true
        }
    }

    if ($null -ne $FallbackUsed) { return $true }
    if ($null -ne $RetryCount) { return $true }
    if (@($AppendFinding).Count -gt 0) { return $true }
    if (@($AppendVerificationSummary).Count -gt 0) { return $true }
    if (@($AppendExecutionLog).Count -gt 0) { return $true }
    if (@($AppendEvent).Count -gt 0) { return $true }
    if (@($AppendModelAttempt).Count -gt 0) { return $true }
    if (@($AppendArtifact).Count -gt 0) { return $true }
    if (@($AppendScope).Count -gt 0) { return $true }
    if (@($AppendConstraint).Count -gt 0) { return $true }
    if (@($AppendRemainingWork).Count -gt 0) { return $true }
    if (@($AppendEvidence).Count -gt 0) { return $true }
    if (@($AppendEventJson).Count -gt 0) { return $true }
    if (@($AppendModelAttemptJson).Count -gt 0) { return $true }

    return $false
}

function Get-FactoryTasksRoot {
    <#
    .SYNOPSIS
    Resolves the canonical Factory tasks directory for the repository.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $tasksRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $ProjectRoot -ChildPath '.trae\factory\tasks'))
    if (-not (Test-Path -LiteralPath $tasksRoot -PathType Container)) {
        throw "Factory tasks directory not found: $tasksRoot"
    }

    return $tasksRoot
}

function Test-IsAbsoluteTaskPath {
    <#
    .SYNOPSIS
    Determines whether a path value is a fully-qualified absolute path.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    return ($PathValue -match '^[A-Za-z]:[\\/]') -or ($PathValue -match '^\\\\')
}

function Test-PathWithinRoot {
    <#
    .SYNOPSIS
    Determines whether a candidate path canonicalizes inside a root directory.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$CandidatePath
    )

    $directorySeparator = [System.IO.Path]::DirectorySeparatorChar.ToString()
    $normalizedRoot = [System.IO.Path]::GetFullPath($RootPath)
    if (-not $normalizedRoot.EndsWith($directorySeparator)) {
        $normalizedRoot = "$normalizedRoot$directorySeparator"
    }

    $normalizedCandidate = [System.IO.Path]::GetFullPath($CandidatePath)
    return $normalizedCandidate.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Initialize-FileLinkInspector {
    [OutputType([void])]
    param()

    if ('FactoryFileLinkInspector' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;

public static class FactoryFileLinkInspector
{
    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        IntPtr hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle hFile,
        StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags);

    public static uint GetLinkCount(SafeFileHandle handle)
    {
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out info))
        {
            throw new IOException("GetFileInformationByHandle failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
        }

        return info.NumberOfLinks;
    }

    public static uint GetFileAttributes(SafeFileHandle handle)
    {
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out info))
        {
            throw new IOException("GetFileInformationByHandle failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
        }

        return info.FileAttributes;
    }

    public static string GetFinalPath(SafeFileHandle handle)
    {
        var buffer = new StringBuilder(512);
        uint result = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
        if (result == 0)
        {
            throw new IOException("GetFinalPathNameByHandle failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
        }

        if (result > buffer.Capacity)
        {
            buffer = new StringBuilder((int)result);
            result = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
            if (result == 0)
            {
                throw new IOException("GetFinalPathNameByHandle failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
            }
        }

        return buffer.ToString();
    }

    public static uint GetLinkCount(string path)
    {
        using (var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        {
            return GetLinkCount(stream.SafeFileHandle);
        }
    }
}
"@
}

function Get-FileLinkCount {
    [OutputType([uint32])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Initialize-FileLinkInspector
    return [FactoryFileLinkInspector]::GetLinkCount($Path)
}

function Initialize-FileIdentityInspector {
    <#
    .SYNOPSIS
    Loads Windows file-identity helpers for stable file identity checks.
    #>
    [OutputType([void])]
    param()

    if ('FactoryFileIdentityInspector' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class FactoryFileIdentityInspector
{
    [StructLayout(LayoutKind.Sequential)]
    public struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        IntPtr hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    public static string GetIdentity(SafeFileHandle handle)
    {
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(handle.DangerousGetHandle(), out info))
        {
            throw new IOException("GetFileInformationByHandle failed with Win32 error " + Marshal.GetLastWin32Error() + ".");
        }

        return string.Format(
            "{0:x8}:{1:x8}:{2:x8}",
            info.VolumeSerialNumber,
            info.FileIndexHigh,
            info.FileIndexLow);
    }

    public static string GetIdentity(string path)
    {
        using (var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        {
            return GetIdentity(stream.SafeFileHandle);
        }
    }
}
"@
}

function Get-FileIdentityFromHandle {
    <#
    .SYNOPSIS
    Returns the stable Windows file identity for an opened file handle.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream
    )

    Initialize-FileIdentityInspector
    return [FactoryFileIdentityInspector]::GetIdentity($Stream.SafeFileHandle)
}

function Get-FileIdentityFromPath {
    <#
    .SYNOPSIS
    Returns the stable Windows file identity for a filesystem path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Initialize-FileIdentityInspector

    try {
        return [FactoryFileIdentityInspector]::GetIdentity($Path)
    }
    catch {
        throw "Failed to read file identity for '$Path': $($_.Exception.Message)"
    }
}

function Assert-TaskFileIdentityMatchesPath {
    <#
    .SYNOPSIS
    Aborts if the target path no longer resolves to the validated task file.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedIdentity
    )

    $currentIdentity = Get-FileIdentityFromPath -Path $Path
    if ($currentIdentity -ne $ExpectedIdentity) {
        throw "Task file identity changed before atomic replace: $Path"
    }
}

function Assert-TaskFileVersionMatchesPath {
    <#
    .SYNOPSIS
    Aborts if the target path no longer matches the validated task file version.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedIdentity,

        [Parameter(Mandatory = $true)]
        [long]$ExpectedLength,

        [Parameter(Mandatory = $true)]
        [long]$ExpectedLastWriteTimeUtcTicks,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedContentFingerprintSha256
    )

    Assert-TaskFileIdentityMatchesPath -Path $Path -ExpectedIdentity $ExpectedIdentity

    try {
        $fileInfo = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to read current task file metadata for '$Path': $($_.Exception.Message)"
    }

    $currentContentFingerprintSha256 = Get-ContentFingerprintSha256FromPath -Path $Path
    if ([long]$fileInfo.Length -ne $ExpectedLength -or [long]$fileInfo.LastWriteTimeUtc.Ticks -ne $ExpectedLastWriteTimeUtcTicks -or $currentContentFingerprintSha256 -ne $ExpectedContentFingerprintSha256) {
        throw "Task file content changed before atomic replace: $Path"
    }
}

function Convert-HandleFinalPathToFullPath {
    <#
    .SYNOPSIS
    Normalizes an opened-handle path into a regular full filesystem path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($Path.StartsWith('\\?\UNC\')) {
        return [System.IO.Path]::GetFullPath(('\\' + $Path.Substring(8)))
    }

    if ($Path.StartsWith('\\?\')) {
        return [System.IO.Path]::GetFullPath($Path.Substring(4))
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-ValidatedTaskFileVersionFromHandle {
    <#
    .SYNOPSIS
    Captures version metadata for the validated opened task file handle.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream
    )

    Initialize-FileLinkInspector
    $validatedPath = Convert-HandleFinalPathToFullPath -Path ([FactoryFileLinkInspector]::GetFinalPath($Stream.SafeFileHandle))

    try {
        $fileLength = [long]$Stream.Length
        $fileInfo = Get-Item -LiteralPath $validatedPath -Force -ErrorAction Stop
        $contentFingerprintSha256 = Get-ContentFingerprintSha256FromStream -Stream $Stream
    }
    catch {
        throw "Failed to read validated task file metadata for '$validatedPath': $($_.Exception.Message)"
    }

    return @{
        length = $fileLength
        last_write_time_utc_ticks = [long]$fileInfo.LastWriteTimeUtc.Ticks
        content_fingerprint_sha256 = $contentFingerprintSha256
    }
}

function Assert-OpenedTaskFileVersionMatchesExpected {
    <#
    .SYNOPSIS
    Aborts if the opened task file handle no longer matches the validated file version.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedIdentity,

        [Parameter(Mandatory = $true)]
        [long]$ExpectedLength,

        [Parameter(Mandatory = $true)]
        [long]$ExpectedLastWriteTimeUtcTicks,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedContentFingerprintSha256
    )

    $currentIdentity = Get-FileIdentityFromHandle -Stream $Stream
    if ($currentIdentity -ne $ExpectedIdentity) {
        throw 'Opened task file identity changed before atomic replace.'
    }

    $currentVersion = Get-ValidatedTaskFileVersionFromHandle -Stream $Stream
    if ([long]$currentVersion.length -ne $ExpectedLength -or [long]$currentVersion.last_write_time_utc_ticks -ne $ExpectedLastWriteTimeUtcTicks -or $currentVersion.content_fingerprint_sha256 -ne $ExpectedContentFingerprintSha256) {
        throw 'Opened task file content changed before atomic replace.'
    }
}

function Assert-ResolvedTaskPathMatchesOpenedTaskFile {
    <#
    .SYNOPSIS
    Aborts if the requested path no longer resolves to the opened task handle path.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream
    )

    Initialize-FileLinkInspector
    $guardedPath = Convert-HandleFinalPathToFullPath -Path ([FactoryFileLinkInspector]::GetFinalPath($Stream.SafeFileHandle))
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.Equals($guardedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Task file path changed after commit guard acquisition: $Path"
    }
}

function Assert-OpenedTaskFileWithinRoot {
    <#
    .SYNOPSIS
    Validates the opened task file handle against the Factory tasks root.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [System.IO.FileStream]$Stream
    )

    Initialize-FileLinkInspector
    $finalPath = Convert-HandleFinalPathToFullPath -Path ([FactoryFileLinkInspector]::GetFinalPath($Stream.SafeFileHandle))
    if (-not (Test-PathWithinRoot -RootPath $RootPath -CandidatePath $finalPath)) {
        throw "Opened task file resolved outside the Factory tasks directory: $finalPath"
    }

    $linkCount = [FactoryFileLinkInspector]::GetLinkCount($Stream.SafeFileHandle)
    if ($linkCount -gt 1) {
        throw "Task file cannot be a hard link or multi-linked file: $finalPath"
    }

    $attributes = [System.IO.FileAttributes]([FactoryFileLinkInspector]::GetFileAttributes($Stream.SafeFileHandle))
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Task file cannot be a reparse-point target: $finalPath"
    }
}

function Open-ValidatedTaskFileForUpdate {
    <#
    .SYNOPSIS
    Opens a task file for update and validates the opened handle.
    #>
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$TasksRoot
    )

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    }
    catch {
        throw "Failed to open task file for update '$Path': $($_.Exception.Message)"
    }

    try {
        Assert-OpenedTaskFileWithinRoot -RootPath $TasksRoot -Stream $stream
        return $stream
    }
    catch {
        $stream.Dispose()
        throw
    }
}

function Open-ValidatedTaskFileForCommitGuard {
    <#
    .SYNOPSIS
    Opens and locks the task file long enough to guard the final replace against in-place writes.
    #>
    [OutputType([System.IO.FileStream])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$TasksRoot
    )

    if (-not (Test-PathWithinRoot -RootPath $TasksRoot -CandidatePath $Path)) {
        throw "Task file must resolve inside the Factory tasks directory: $TasksRoot"
    }

    Assert-DirectTaskFile -Path $Path
    Assert-NoReparsePointsInPath -RootPath $TasksRoot -TargetPath $Path

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    }
    catch {
        throw "Failed to open task file commit guard '$Path': $($_.Exception.Message)"
    }

    try {
        Assert-OpenedTaskFileWithinRoot -RootPath $TasksRoot -Stream $stream
        $stream.Lock(0, [long]::MaxValue)
        return $stream
    }
    catch {
        $stream.Dispose()
        throw
    }
}

function Assert-DirectTaskFile {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $taskItem = Get-Item -LiteralPath $Path -Force
    if (-not [string]::IsNullOrWhiteSpace($taskItem.LinkType)) {
        throw "Task file cannot be a link: $Path"
    }

    if (Test-HasMaterialLinkTarget -Target $taskItem.Target) {
        throw "Task file cannot target another path: $Path"
    }

    if ((Get-FileLinkCount -Path $Path) -gt 1) {
        throw "Task file cannot be a hard link or multi-linked file: $Path"
    }
}

function Assert-NoReparsePointsInPath {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $currentPath = $TargetPath
    while ($true) {
        $currentItem = Get-Item -LiteralPath $currentPath -Force
        if (($currentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Task path cannot traverse a reparse point: $currentPath"
        }

        if ($currentPath.Equals($RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $parentPath = Split-Path -Parent $currentPath
        if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath.Equals($currentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $currentPath = $parentPath
    }
}

function Resolve-TaskFilePath {
    <#
    .SYNOPSIS
    Resolves and validates the task file path inside the Factory tasks directory.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    $tasksRoot = Get-FactoryTasksRoot -ProjectRoot $ProjectRoot
    if (Test-IsAbsoluteTaskPath -PathValue $PathValue) {
        $resolvedPath = [System.IO.Path]::GetFullPath($PathValue)
    }
    else {
        $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $tasksRoot -ChildPath $PathValue))
    }

    if (-not (Test-PathWithinRoot -RootPath $tasksRoot -CandidatePath $resolvedPath)) {
        throw "TaskPath must resolve inside the Factory tasks directory: $tasksRoot"
    }

    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.json') {
        throw "Factory V2 task state update expects a JSON task file: $resolvedPath"
    }

    $resolvedLeafName = Split-Path -Leaf $resolvedPath
    if ($resolvedLeafName -like '.*.last-known-good.json') {
        throw "TaskPath must reference a canonical Factory task file, not an internal recovery backup: $resolvedPath"
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Task file not found: $resolvedPath"
    }

    Assert-DirectTaskFile -Path $resolvedPath
    Assert-NoReparsePointsInPath -RootPath $tasksRoot -TargetPath $resolvedPath
    return $resolvedPath
}

function Main {
    [OutputType([void])]
    param()

    if (-not (Test-HasRequestedChange)) {
        throw 'No updates were requested.'
    }

    $projectRoot = Get-ProjectRoot
    $contract = Get-TaskStateContract -ProjectRoot $projectRoot
    $tasksRoot = Get-FactoryTasksRoot -ProjectRoot $projectRoot
    $taskFilePath = Resolve-TaskFilePath -ProjectRoot $projectRoot -PathValue $TaskPath
    $taskFileStream = $null
    [string]$resolvedTaskContent = $null
    [hashtable]$state = $null

    try {
        $taskFileStream = Open-ValidatedTaskFileForUpdate -Path $taskFilePath -TasksRoot $tasksRoot
        $state = Read-TaskState -Stream $taskFileStream -DisplayPath $taskFilePath -ResolvedContent ([ref]$resolvedTaskContent)
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')

        if (-not [string]::IsNullOrWhiteSpace($SetFieldJson)) {
            Apply-JsonFieldUpdates -State $state -JsonText $SetFieldJson -Contract $contract
        }

        if (-not [string]::IsNullOrWhiteSpace($Priority)) {
            Assert-ValidatedTaskStateFieldValue -FieldName 'priority' -Value $Priority -Contract $contract
            $state.priority = $Priority
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentPhase)) {
            Assert-ValidatedTaskStateFieldValue -FieldName 'current_phase' -Value $CurrentPhase -Contract $contract
            $state.current_phase = $CurrentPhase
        }

    if (-not [string]::IsNullOrWhiteSpace($CurrentRole)) {
        Assert-ValidatedTaskStateFieldValue -FieldName 'current_role' -Value $CurrentRole -Contract $contract
        $state.current_role = $CurrentRole
    }

    if (-not [string]::IsNullOrWhiteSpace($CurrentModel)) {
        $state.current_model = $CurrentModel
    }

    if ($null -ne $FallbackUsed) {
        $state.fallback_used = [bool]$FallbackUsed
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        Assert-ValidatedTaskStateFieldValue -FieldName 'status' -Value $Status -Contract $contract
        $state.status = $Status
    }

    if ($null -ne $RetryCount) {
        $state.retry_count = [int]$RetryCount
    }

    if ($PSBoundParameters.ContainsKey('Blocker')) {
        $state.blocker = $Blocker
    }

    if ($PSBoundParameters.ContainsKey('NextAutomaticAction')) {
        $state.next_automatic_action = $NextAutomaticAction
    }

    if ($PSBoundParameters.ContainsKey('EscalationReason')) {
        $state.escalation_reason = $EscalationReason
    }

    if ($PSBoundParameters.ContainsKey('FinalOutcome')) {
        $state.final_outcome = $FinalOutcome
    }

    if (-not [string]::IsNullOrWhiteSpace($CapabilityClassification)) {
        $state.capability_classification.orchestration_mode = $CapabilityClassification
    }

    if (-not [string]::IsNullOrWhiteSpace($ReviewStatus)) {
        Assert-ValidatedTaskStateFieldValue -FieldName 'review_result' -Value $ReviewStatus -Contract $contract
        $state.review_result = $ReviewStatus
    }

    if (-not [string]::IsNullOrWhiteSpace($SecurityStatus)) {
        Assert-ValidatedTaskStateFieldValue -FieldName 'security_result' -Value $SecurityStatus -Contract $contract
        $state.security_result = $SecurityStatus
    }

    if (-not [string]::IsNullOrWhiteSpace($QaStatus)) {
        Assert-ValidatedTaskStateFieldValue -FieldName 'qa_result' -Value $QaStatus -Contract $contract
        $state.qa_result = $QaStatus
    }

    $state.findings = Add-StringEntries -Existing (Ensure-List -Value $state.findings) -Items $AppendFinding
    $state.scope = Add-StringEntries -Existing (Ensure-List -Value $state.scope) -Items $AppendScope
    $state.constraints = Add-StringEntries -Existing (Ensure-List -Value $state.constraints) -Items $AppendConstraint
    $state.remaining_work = Add-StringEntries -Existing (Ensure-List -Value $state.remaining_work) -Items $AppendRemainingWork
    $state.evidence = Add-StringEntries -Existing (Ensure-List -Value $state.evidence) -Items ($AppendEvidence + $AppendArtifact)
    $state.verification_summary = Append-TextBlock -Existing $state.verification_summary -Items $AppendVerificationSummary
    $state.execution_log = Add-ExecutionLogEntries -Existing (Ensure-List -Value $state.execution_log) -Items $AppendExecutionLog -Timestamp $timestamp -Role $state.current_role
    $state.events = Add-EventEntries -Existing (Ensure-List -Value $state.events) -Items $AppendEvent -Timestamp $timestamp -Role $state.current_role
    $state.events = Add-JsonEntries -Existing (Ensure-List -Value $state.events) -Items $AppendEventJson -DestinationField 'events'
    $state.model_attempts = Add-ModelAttemptEntries `
        -Existing (Ensure-List -Value $state.model_attempts) `
        -Items $AppendModelAttempt `
        -Timestamp $timestamp `
        -Role $state.current_role `
        -Model $state.current_model `
        -WasFallback $FallbackUsed
    $state.updated_at = $timestamp
    $state.model_attempts = Add-JsonEntries -Existing (Ensure-List -Value $state.model_attempts) -Items $AppendModelAttemptJson -DestinationField 'model_attempts'
        Assert-TaskStateContract -State $state -Contract $contract

        Write-TaskState `
            -Stream $taskFileStream `
            -State $state `
            -TaskFilePath $taskFilePath `
            -TasksRoot $tasksRoot `
            -PreviousContent $resolvedTaskContent
    }
    finally {
        if ($null -ne $taskFileStream) {
            $taskFileStream.Dispose()
        }
    }

    Write-Host "Updated factory task: $taskFilePath"
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
