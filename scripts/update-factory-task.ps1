<#
.SYNOPSIS
Safely updates an existing factory task record.

.DESCRIPTION
Updates supported task metadata fields in an existing markdown task record and
optionally appends bullet items to recovery-oriented sections such as Findings,
Remaining Work, Execution Log, and Evidence.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Phase,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResponsibleAgent,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Status,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ReviewResult,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$SecurityResult,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TestResult,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$FinalApproval,

    [Parameter()]
    [string[]]$AppendFinding = @(),

    [Parameter()]
    [string[]]$AppendRemainingWork = @(),

    [Parameter()]
    [string[]]$AppendExecutionLog = @(),

    [Parameter()]
    [string[]]$AppendEvidence = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Resolves the repository root from this script location.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return [System.IO.Path]::GetFullPath($projectRoot)
}

function Get-TaskDirectoryPath {
    <#
    .SYNOPSIS
    Returns the absolute path to the tracked task directory.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $taskDirectoryPath = Join-Path -Path $ProjectRoot -ChildPath '.trae\factory\tasks'
    if (-not (Test-Path -LiteralPath $taskDirectoryPath -PathType Container)) {
        throw "Task directory not found at: $taskDirectoryPath"
    }

    return [System.IO.Path]::GetFullPath($taskDirectoryPath)
}

function Resolve-TaskFilePath {
    <#
    .SYNOPSIS
    Resolves and validates the task file path.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$TaskDirectoryPath,

        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    $candidatePath = $PathValue
    if (-not [System.IO.Path]::IsPathRooted($candidatePath)) {
        $candidatePath = Join-Path -Path $ProjectRoot -ChildPath $candidatePath
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($candidatePath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Task file not found: $resolvedPath"
    }

    if ([System.IO.Path]::GetExtension($resolvedPath) -ne '.md') {
        throw "Task file must be a markdown file: $resolvedPath"
    }

    $taskDirectoryPrefix = '{0}{1}' -f $TaskDirectoryPath.TrimEnd('\'), '\'
    if (-not $resolvedPath.StartsWith($taskDirectoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Task file must be located under the tracked tasks directory: $TaskDirectoryPath"
    }

    Assert-DirectTaskFile -Path $resolvedPath
    Assert-NoReparsePointsInPath -RootPath $TaskDirectoryPath -TargetPath $resolvedPath
    return $resolvedPath
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

    if (@($taskItem.Target).Count -gt 0) {
        throw "Task file cannot target another path: $Path"
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

function Read-Utf8Text {
    <#
    .SYNOPSIS
    Reads UTF-8 text from disk.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8NoBomText {
    <#
    .SYNOPSIS
    Writes UTF-8 text without a BOM.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function ConvertTo-NormalizedNewlines {
    <#
    .SYNOPSIS
    Normalizes line endings to LF for in-memory editing.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return $Content -replace "`r`n", "`n"
}

function ConvertTo-WindowsNewlines {
    <#
    .SYNOPSIS
    Converts normalized LF text back to CRLF.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return $Content -replace "`n", "`r`n"
}

function Set-MetadataFieldValue {
    <#
    .SYNOPSIS
    Replaces a supported metadata bullet value.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $pattern = '^- {0}: .*$' -f [System.Text.RegularExpressions.Regex]::Escape($FieldName)
    $regex = [System.Text.RegularExpressions.Regex]::new(
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )

    if (-not $regex.IsMatch($Content)) {
        throw "Task file does not contain the required field '- ${FieldName}: ...'."
    }

    $replacementLine = "- ${FieldName}: $Value"
    $matchEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$Match)
        return $replacementLine
    }

    return $regex.Replace($Content, $matchEvaluator, 1)
}

function Get-TrackedSectionOrder {
    <#
    .SYNOPSIS
    Returns the supported top-level task sections in preferred order.
    #>
    [OutputType([string[]])]
    param()

    return @(
        'Plan'
        'Findings'
        'Execution Log'
        'Evidence'
        'Retry History'
        'Capability Classification'
        'Review Result'
        'Security Result'
        'Test Result'
        'Remaining Work'
        'Final Approval'
    )
}

function New-SectionBlock {
    <#
    .SYNOPSIS
    Builds a markdown section block.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter(Mandatory = $true)]
        [string[]]$BulletItems
    )

    $body = ($BulletItems | ForEach-Object { '- {0}' -f $_ }) -join "`n"
    return "## $SectionName`n$body`n`n"
}

function Ensure-TaskSection {
    <#
    .SYNOPSIS
    Ensures a supported section exists in the task file.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SectionName
    )

    $sectionPattern = '(?m)^## {0}\s*$' -f [System.Text.RegularExpressions.Regex]::Escape($SectionName)
    if ([System.Text.RegularExpressions.Regex]::IsMatch($Content, $sectionPattern)) {
        return $Content
    }

    $defaultBlock = switch ($SectionName) {
        'Execution Log' { New-SectionBlock -SectionName $SectionName -BulletItems @('No execution recorded yet.') }
        'Evidence' { New-SectionBlock -SectionName $SectionName -BulletItems @('None yet.') }
        default { New-SectionBlock -SectionName $SectionName -BulletItems @('Pending') }
    }

    $sectionOrder = Get-TrackedSectionOrder
    $sectionIndex = [Array]::IndexOf($sectionOrder, $SectionName)
    if ($sectionIndex -lt 0) {
        throw "Unsupported task section: $SectionName"
    }

    for ($index = $sectionIndex + 1; $index -lt $sectionOrder.Count; $index++) {
        $nextSectionName = $sectionOrder[$index]
        $nextPattern = '(?m)^## {0}\s*$' -f [System.Text.RegularExpressions.Regex]::Escape($nextSectionName)
        $nextMatch = [System.Text.RegularExpressions.Regex]::Match($Content, $nextPattern)
        if ($nextMatch.Success) {
            return $Content.Insert($nextMatch.Index, $defaultBlock)
        }
    }

    if (-not $Content.EndsWith("`n")) {
        $Content += "`n"
    }

    if (-not $Content.EndsWith("`n`n")) {
        $Content += "`n"
    }

    return $Content + $defaultBlock
}

function ConvertTo-BulletItems {
    <#
    .SYNOPSIS
    Normalizes free-form input into non-empty bullet items.
    #>
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [string[]]$Items
    )

    $normalizedItems = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        $trimmedItem = $item.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmedItem)) {
            $normalizedItems.Add($trimmedItem)
        }
    }

    return $normalizedItems.ToArray()
}

function Test-IsPlaceholderSectionBody {
    <#
    .SYNOPSIS
    Determines whether a section still contains only placeholder bullets.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return $true
    }

    $lines = @($Body.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if (@($lines).Count -eq 0) {
        return $true
    }

    foreach ($line in $lines) {
        if ($line -notmatch '^- (Pending|None(?: yet\.)?|No execution recorded yet\.)$') {
            return $false
        }
    }

    return $true
}

function Add-SectionBullets {
    <#
    .SYNOPSIS
    Appends bullet items to a supported section.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter()]
        [AllowNull()]
        [string[]]$Items
    )

    $bulletItems = @(ConvertTo-BulletItems -Items $Items)
    if (@($bulletItems).Count -eq 0) {
        return $Content
    }

    $updatedContent = Ensure-TaskSection -Content $Content -SectionName $SectionName
    $sectionPattern = '(?ms)^## {0}\s*\n(?<body>.*?)(?=^## |\z)' -f [System.Text.RegularExpressions.Regex]::Escape($SectionName)
    $match = [System.Text.RegularExpressions.Regex]::Match($updatedContent, $sectionPattern)
    if (-not $match.Success) {
        throw "Unable to locate section after ensuring it exists: $SectionName"
    }

    $existingBody = $match.Groups['body'].Value.Trim("`n")
    $mergedBulletLines = New-Object System.Collections.Generic.List[string]

    if (-not (Test-IsPlaceholderSectionBody -Body $existingBody)) {
        foreach ($existingLine in $existingBody.Split("`n")) {
            $trimmedLine = $existingLine.TrimEnd()
            if ($trimmedLine -ne '') {
                $mergedBulletLines.Add($trimmedLine)
            }
        }
    }

    foreach ($bulletItem in $bulletItems) {
        $mergedBulletLines.Add('- {0}' -f $bulletItem)
    }

    $replacementBlock = "## $SectionName`n{0}`n`n" -f ($mergedBulletLines -join "`n")
    $before = $updatedContent.Substring(0, $match.Index)
    $after = $updatedContent.Substring($match.Index + $match.Length)
    return $before + $replacementBlock + $after
}

function Set-SectionBullets {
    <#
    .SYNOPSIS
    Replaces a supported section body with the supplied bullet items.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SectionName,

        [Parameter()]
        [AllowNull()]
        [string[]]$Items
    )

    $bulletItems = @(ConvertTo-BulletItems -Items $Items)
    if (@($bulletItems).Count -eq 0) {
        throw "No replacement value was supplied for section: $SectionName"
    }

    $updatedContent = Ensure-TaskSection -Content $Content -SectionName $SectionName
    $sectionPattern = '(?ms)^## {0}\s*\n(?<body>.*?)(?=^## |\z)' -f [System.Text.RegularExpressions.Regex]::Escape($SectionName)
    $match = [System.Text.RegularExpressions.Regex]::Match($updatedContent, $sectionPattern)
    if (-not $match.Success) {
        throw "Unable to locate section after ensuring it exists: $SectionName"
    }

    $replacementBlock = "## $SectionName`n{0}`n`n" -f (($bulletItems | ForEach-Object { '- {0}' -f $_ }) -join "`n")
    $before = $updatedContent.Substring(0, $match.Index)
    $after = $updatedContent.Substring($match.Index + $match.Length)
    return $before + $replacementBlock + $after
}

function Test-HasAnyRequestedChange {
    <#
    .SYNOPSIS
    Indicates whether the caller supplied at least one update operation.
    #>
    [OutputType([bool])]
    param()

    $scalarValues = @(
        $Phase,
        $ResponsibleAgent,
        $Status,
        $ReviewResult,
        $SecurityResult,
        $TestResult,
        $FinalApproval
    )

    foreach ($value in $scalarValues) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $true
        }
    }

    if (@(ConvertTo-BulletItems -Items $AppendFinding).Count -gt 0) { return $true }
    if (@(ConvertTo-BulletItems -Items $AppendRemainingWork).Count -gt 0) { return $true }
    if (@(ConvertTo-BulletItems -Items $AppendExecutionLog).Count -gt 0) { return $true }
    if (@(ConvertTo-BulletItems -Items $AppendEvidence).Count -gt 0) { return $true }

    return $false
}

function Main {
    <#
    .SYNOPSIS
    Applies safe task record updates and writes them back to disk.
    #>
    [OutputType([void])]
    param()

    if (-not (Test-HasAnyRequestedChange)) {
        throw 'No updates were requested. Supply at least one field update or append operation.'
    }

    $projectRoot = Get-ProjectRoot
    $taskDirectoryPath = Get-TaskDirectoryPath -ProjectRoot $projectRoot
    $taskFilePath = Resolve-TaskFilePath `
        -ProjectRoot $projectRoot `
        -TaskDirectoryPath $taskDirectoryPath `
        -PathValue $TaskPath

    $taskContent = Read-Utf8Text -Path $taskFilePath
    $taskContent = ConvertTo-NormalizedNewlines -Content $taskContent

    if (-not $taskContent.StartsWith('# Task Record')) {
        throw "Task file does not appear to use the tracked task format: $taskFilePath"
    }

    if (-not [string]::IsNullOrWhiteSpace($Phase)) {
        $taskContent = Set-MetadataFieldValue -Content $taskContent -FieldName 'Phase' -Value $Phase
    }

    if (-not [string]::IsNullOrWhiteSpace($ResponsibleAgent)) {
        $taskContent = Set-MetadataFieldValue -Content $taskContent -FieldName 'Responsible agent' -Value $ResponsibleAgent
    }

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $taskContent = Set-MetadataFieldValue -Content $taskContent -FieldName 'Status' -Value $Status
    }

    if (-not [string]::IsNullOrWhiteSpace($ReviewResult)) {
        $taskContent = Set-SectionBullets -Content $taskContent -SectionName 'Review Result' -Items @($ReviewResult)
    }

    if (-not [string]::IsNullOrWhiteSpace($SecurityResult)) {
        $taskContent = Set-SectionBullets -Content $taskContent -SectionName 'Security Result' -Items @($SecurityResult)
    }

    if (-not [string]::IsNullOrWhiteSpace($TestResult)) {
        $taskContent = Set-SectionBullets -Content $taskContent -SectionName 'Test Result' -Items @($TestResult)
    }

    if (-not [string]::IsNullOrWhiteSpace($FinalApproval)) {
        $taskContent = Set-SectionBullets -Content $taskContent -SectionName 'Final Approval' -Items @($FinalApproval)
    }

    $taskContent = Add-SectionBullets -Content $taskContent -SectionName 'Findings' -Items $AppendFinding
    $taskContent = Add-SectionBullets -Content $taskContent -SectionName 'Remaining Work' -Items $AppendRemainingWork
    $taskContent = Add-SectionBullets -Content $taskContent -SectionName 'Execution Log' -Items $AppendExecutionLog
    $taskContent = Add-SectionBullets -Content $taskContent -SectionName 'Evidence' -Items $AppendEvidence

    $taskContent = $taskContent.TrimEnd("`n") + "`n"
    $taskContent = ConvertTo-WindowsNewlines -Content $taskContent
    Write-Utf8NoBomText -Path $taskFilePath -Content $taskContent

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
