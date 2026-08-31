<#
.SYNOPSIS
Initializes factory project identity for the current repository or an external adoption target.

.DESCRIPTION
Updates the project-facing identity in `README.md` and `.trae/current-project-state.md`
for the selected target root. The script supports check-only mode by default, can seed
missing files from the baseline repository, and skips custom adopter-owned README files
instead of overwriting them silently.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter()]
    [string]$ProjectSummary = '',

    [Parameter()]
    [string]$TargetProjectRoot = '',

    [switch]$CheckOnly
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

function Resolve-TargetProjectRoot {
    <#
    .SYNOPSIS
    Resolves the target root and records whether it already exists.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTargetRoot,

        [Parameter(Mandatory = $true)]
        [string]$FallbackProjectRoot
    )

    $effectiveRoot = if ([string]::IsNullOrWhiteSpace($RequestedTargetRoot)) { $FallbackProjectRoot } else { $RequestedTargetRoot }
    $fullPath = [System.IO.Path]::GetFullPath($effectiveRoot)

    if (Test-Path -LiteralPath $fullPath) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw "Target project root exists but is not a directory: $fullPath"
        }

        return [pscustomobject]@{
            Path = $fullPath
            Exists = $true
        }
    }

    return [pscustomobject]@{
        Path = $fullPath
        Exists = $false
    }
}

function Ensure-TargetRoot {
    <#
    .SYNOPSIS
    Creates the target project root when apply mode needs it.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot
    )

    if (Test-Path -LiteralPath $TargetRoot -PathType Container) {
        return $false
    }

    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    return $true
}

function Get-EffectiveProjectSummary {
    <#
    .SYNOPSIS
    Returns the summary text to persist in tracked files.
    #>
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Summary
    )

    if ([string]::IsNullOrWhiteSpace($Summary)) {
        return 'TODO'
    }

    return $Summary.Trim()
}

function Get-DetectedNewLine {
    <#
    .SYNOPSIS
    Detects the newline sequence used in a text blob.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    if ($Content.Contains("`r`n")) {
        return "`r`n"
    }

    return [Environment]::NewLine
}

function Split-Lines {
    <#
    .SYNOPSIS
    Splits text into lines while preserving empty trailing segments.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return $Content -split '\r?\n', -1
}

function Test-ReadmeSupportsFactoryIdentityUpdate {
    <#
    .SYNOPSIS
    Returns true only when README still uses the baseline identity-header shape.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $lines = Split-Lines -Content $Content
    if ($lines.Count -lt 2) {
        return $false
    }

    if ($lines[1] -match '^> Project summary:') {
        return $true
    }

    if ($lines.Count -gt 2 -and [string]::IsNullOrWhiteSpace($lines[1]) -and $lines[2] -match '^> Project summary:') {
        return $true
    }

    return $false
}

function Get-UpdatedReadmeContent {
    <#
    .SYNOPSIS
    Returns the updated README content with the project identity header block.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectSummary
    )

    $newLine = Get-DetectedNewLine -Content $Content
    $lines = Split-Lines -Content $Content

    if ($lines.Count -eq 0) {
        $lines = @('')
    }

    $bodyStartIndex = 1

    if ($lines.Count -gt 1 -and $lines[1] -match '^> Project summary:') {
        $bodyStartIndex = 2
    }
    elseif ($lines.Count -gt 2 -and [string]::IsNullOrWhiteSpace($lines[1]) -and $lines[2] -match '^> Project summary:') {
        $bodyStartIndex = 3
    }

    if ($lines.Count -gt $bodyStartIndex -and [string]::IsNullOrWhiteSpace($lines[$bodyStartIndex])) {
        $bodyStartIndex++
    }

    $newLines = New-Object System.Collections.Generic.List[string]
    $newLines.Add("# $ProjectName")
    $newLines.Add("> Project summary: $ProjectSummary")
    $newLines.Add('')

    for ($index = $bodyStartIndex; $index -lt $lines.Count; $index++) {
        $newLines.Add($lines[$index])
    }

    $updatedContent = $newLines -join $newLine
    if (-not $updatedContent.EndsWith($newLine)) {
        $updatedContent += $newLine
    }

    return $updatedContent
}

function Get-ProjectIdentitySection {
    <#
    .SYNOPSIS
    Builds the markdown Project Identity section.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectSummary,

        [Parameter(Mandatory = $true)]
        [string]$NewLine
    )

    return @(
        '## Project Identity'
        ''
        "- Name: $ProjectName"
        "- Summary: $ProjectSummary"
    ) -join $NewLine
}

function Get-UpdatedProjectStateContent {
    <#
    .SYNOPSIS
    Returns the updated current-project-state content with Project Identity near the top.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectSummary
    )

    $newLine = Get-DetectedNewLine -Content $Content
    $projectIdentitySection = Get-ProjectIdentitySection -ProjectName $ProjectName -ProjectSummary $ProjectSummary -NewLine $newLine
    $lines = Split-Lines -Content $Content

    $projectIdentityStartIndex = -1
    $projectIdentityEndIndex = $lines.Count
    $firstSectionStartIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($firstSectionStartIndex -lt 0 -and $lines[$index] -match '^## ') {
            $firstSectionStartIndex = $index
        }

        if ($lines[$index] -eq '## Project Identity') {
            $projectIdentityStartIndex = $index
            continue
        }

        if ($projectIdentityStartIndex -ge 0 -and $lines[$index] -match '^## ') {
            $projectIdentityEndIndex = $index
            break
        }
    }

    $prefixLines = New-Object System.Collections.Generic.List[string]
    $suffixLines = New-Object System.Collections.Generic.List[string]

    if ($projectIdentityStartIndex -ge 0) {
        for ($index = 0; $index -lt $projectIdentityStartIndex; $index++) {
            $prefixLines.Add($lines[$index])
        }

        for ($index = $projectIdentityEndIndex; $index -lt $lines.Count; $index++) {
            $suffixLines.Add($lines[$index])
        }
    }
    elseif ($firstSectionStartIndex -ge 0) {
        for ($index = 0; $index -lt $firstSectionStartIndex; $index++) {
            $prefixLines.Add($lines[$index])
        }

        for ($index = $firstSectionStartIndex; $index -lt $lines.Count; $index++) {
            $suffixLines.Add($lines[$index])
        }
    }
    else {
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $prefixLines.Add($lines[$index])
        }
    }

    while ($prefixLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($prefixLines[$prefixLines.Count - 1])) {
        $prefixLines.RemoveAt($prefixLines.Count - 1)
    }

    while ($suffixLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($suffixLines[0])) {
        $suffixLines.RemoveAt(0)
    }

    $updatedLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $prefixLines) {
        $updatedLines.Add($line)
    }

    if ($updatedLines.Count -gt 0) {
        $updatedLines.Add('')
    }

    foreach ($line in (Split-Lines -Content $projectIdentitySection)) {
        $updatedLines.Add($line)
    }

    if ($suffixLines.Count -gt 0) {
        $updatedLines.Add('')
        foreach ($line in $suffixLines) {
            $updatedLines.Add($line)
        }
    }

    $updatedContent = $updatedLines -join $newLine

    if (-not $updatedContent.EndsWith($newLine)) {
        $updatedContent += $newLine
    }

    return $updatedContent
}

function Write-Utf8File {
    <#
    .SYNOPSIS
    Writes UTF-8 content without a BOM.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Encoding)
}

function Get-NormalizedComparableText {
    <#
    .SYNOPSIS
    Normalizes text for stable change detection across newline variations.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $normalizedContent = $Content -replace "`r`n", "`n"
    return $normalizedContent.TrimEnd("`r", "`n")
}

function Get-BaselineSeedContent {
    <#
    .SYNOPSIS
    Returns the baseline content for a tracked file used as a seed.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaselineRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $seedPath = Join-Path -Path $BaselineRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $seedPath -PathType Leaf)) {
        throw "Baseline seed file not found at: $seedPath"
    }

    return Get-Content -LiteralPath $seedPath -Raw
}

function Ensure-ParentDirectory {
    <#
    .SYNOPSIS
    Creates a file's parent directory when needed.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parentPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
}

function New-InitializationFileResult {
    <#
    .SYNOPSIS
    Creates a normalized per-file initialization result.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [bool]$TargetExistedBeforeRun,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [pscustomobject]@{
        RelativePath = $RelativePath
        Status = $Status
        TargetExistedBeforeRun = $TargetExistedBeforeRun
        Message = $Message
    }
}

function Get-ReadmeInitializationResult {
    <#
    .SYNOPSIS
    Calculates the README initialization result and optional updated content.
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
        [string]$ProjectSummary
    )

    $relativePath = 'README.md'
    $targetPath = Join-Path -Path $TargetRoot -ChildPath $relativePath
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
    $sourceContent = if ($targetExists) {
        Get-Content -LiteralPath $targetPath -Raw
    }
    else {
        Get-BaselineSeedContent -BaselineRoot $BaselineRoot -RelativePath $relativePath
    }

    if ($targetExists -and -not (Test-ReadmeSupportsFactoryIdentityUpdate -Content $sourceContent)) {
        return [pscustomobject]@{
            RelativePath = $relativePath
            TargetPath = $targetPath
            TargetExistsBeforeRun = $targetExists
            ShouldWrite = $false
            Content = $null
            Result = (New-InitializationFileResult -RelativePath $relativePath -Status 'manual_review_required' -TargetExistedBeforeRun $targetExists -Message 'README.md uses a custom structure; skipped automatic identity update.')
            ManualFollowUp = 'README.md already exists with a custom structure. Update the project title/summary manually if you want the factory identity header.'
        }
    }

    $updatedContent = Get-UpdatedReadmeContent -Content $sourceContent -ProjectName $ProjectName -ProjectSummary $ProjectSummary
    $hasChanges = (Get-NormalizedComparableText -Content $updatedContent) -cne (Get-NormalizedComparableText -Content $sourceContent)

    $status = if (-not $targetExists) {
        'create_from_seed'
    }
    elseif ($hasChanges) {
        'update_identity'
    }
    else {
        'already_aligned'
    }

    $message = switch ($status) {
        'create_from_seed' { 'README.md will be created from the baseline seed with the requested project identity.' }
        'update_identity' { 'README.md identity header will be updated.' }
        default { 'README.md is already aligned with the requested project identity.' }
    }

    return [pscustomobject]@{
        RelativePath = $relativePath
        TargetPath = $targetPath
        TargetExistsBeforeRun = $targetExists
        ShouldWrite = (-not $targetExists) -or $hasChanges
        Content = $updatedContent
        Result = (New-InitializationFileResult -RelativePath $relativePath -Status $status -TargetExistedBeforeRun $targetExists -Message $message)
        ManualFollowUp = $null
    }
}

function Get-ProjectStateInitializationResult {
    <#
    .SYNOPSIS
    Calculates the current-project-state initialization result and updated content.
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
        [string]$ProjectSummary
    )

    $relativePath = '.trae/current-project-state.md'
    $targetPath = Join-Path -Path $TargetRoot -ChildPath $relativePath
    $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
    $sourceContent = if ($targetExists) {
        Get-Content -LiteralPath $targetPath -Raw
    }
    else {
        Get-BaselineSeedContent -BaselineRoot $BaselineRoot -RelativePath $relativePath
    }

    $updatedContent = Get-UpdatedProjectStateContent -Content $sourceContent -ProjectName $ProjectName -ProjectSummary $ProjectSummary
    $hasChanges = (Get-NormalizedComparableText -Content $updatedContent) -cne (Get-NormalizedComparableText -Content $sourceContent)

    $status = if (-not $targetExists) {
        'create_from_seed'
    }
    elseif ($hasChanges) {
        'update_identity'
    }
    else {
        'already_aligned'
    }

    $message = switch ($status) {
        'create_from_seed' { '.trae/current-project-state.md will be created from the baseline seed with the requested project identity.' }
        'update_identity' { '.trae/current-project-state.md Project Identity section will be updated.' }
        default { '.trae/current-project-state.md already contains the requested project identity.' }
    }

    return [pscustomobject]@{
        RelativePath = $relativePath
        TargetPath = $targetPath
        TargetExistsBeforeRun = $targetExists
        ShouldWrite = (-not $targetExists) -or $hasChanges
        Content = $updatedContent
        Result = (New-InitializationFileResult -RelativePath $relativePath -Status $status -TargetExistedBeforeRun $targetExists -Message $message)
        ManualFollowUp = $null
    }
}

function Write-InitializationPreview {
    <#
    .SYNOPSIS
    Prints a concise preview or apply summary for initialization.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly,

        [Parameter(Mandatory = $true)]
        [bool]$TargetRootExistedBeforeRun,

        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$FileResults,

        [object[]]$ManualFollowUps = @()
    )

    Write-Host ("Initialization target: {0}" -f $TargetRoot)
    Write-Host ("Mode: {0}" -f $(if ($IsCheckOnly) { 'check-only' } else { 'apply' }))
    Write-Host ("Target root status: {0}" -f $(if ($TargetRootExistedBeforeRun) { 'existing' } else { 'will_create_on_apply' }))

    foreach ($fileResult in $FileResults) {
        Write-Host ("[{0}] {1} - {2}" -f $fileResult.Status.ToUpperInvariant(), $fileResult.RelativePath, $fileResult.Message)
    }

    if ($ManualFollowUps.Count -gt 0) {
        Write-Host 'Manual follow-ups:'
        foreach ($followUp in $ManualFollowUps) {
            Write-Host "- $followUp"
        }
    }
}

function Main {
    <#
    .SYNOPSIS
    Validates inputs and applies or previews project identity initialization.
    #>
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedProjectName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RequestedProjectSummary,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RequestedTargetRoot,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $trimmedProjectName = $RequestedProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedProjectName)) {
        throw 'ProjectName must contain at least one non-whitespace character.'
    }

    $baselineRoot = Get-BaselineProjectRoot
    $targetInfo = Resolve-TargetProjectRoot -RequestedTargetRoot $RequestedTargetRoot -FallbackProjectRoot $baselineRoot
    $effectiveSummary = Get-EffectiveProjectSummary -Summary $RequestedProjectSummary

    $readmePlan = Get-ReadmeInitializationResult -BaselineRoot $baselineRoot -TargetRoot $targetInfo.Path -ProjectName $trimmedProjectName -ProjectSummary $effectiveSummary
    $projectStatePlan = Get-ProjectStateInitializationResult -BaselineRoot $baselineRoot -TargetRoot $targetInfo.Path -ProjectName $trimmedProjectName -ProjectSummary $effectiveSummary

    $fileResults = @($readmePlan.Result, $projectStatePlan.Result)
    $manualFollowUps = @($readmePlan.ManualFollowUp, $projectStatePlan.ManualFollowUp | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    Write-InitializationPreview -TargetRoot $targetInfo.Path -IsCheckOnly $IsCheckOnly -TargetRootExistedBeforeRun $targetInfo.Exists -FileResults $fileResults -ManualFollowUps $manualFollowUps

    $targetRootCreated = $false
    if (-not $IsCheckOnly) {
        $targetRootCreated = Ensure-TargetRoot -TargetRoot $targetInfo.Path

        foreach ($plan in @($readmePlan, $projectStatePlan)) {
            if (-not $plan.ShouldWrite) {
                continue
            }

            Ensure-ParentDirectory -Path $plan.TargetPath
            Write-Utf8File -Path $plan.TargetPath -Content $plan.Content
        }

        Write-Host 'Project initialization completed successfully.'
    }
    else {
        Write-Host 'Check-only mode: no files will be modified.'
    }

    return [pscustomobject]@{
        TargetRoot = $targetInfo.Path
        Mode = if ($IsCheckOnly) { 'check-only' } else { 'apply' }
        TargetRootExistedBeforeRun = $targetInfo.Exists
        TargetRootCreated = $targetRootCreated
        ProjectName = $trimmedProjectName
        ProjectSummary = $effectiveSummary
        FileResults = $fileResults
        ManualFollowUps = $manualFollowUps
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Main -RequestedProjectName $ProjectName -RequestedProjectSummary $ProjectSummary -RequestedTargetRoot $TargetProjectRoot -IsCheckOnly $CheckOnly.IsPresent
    }
    catch {
        Write-Error $_
        exit 1
    }
}
