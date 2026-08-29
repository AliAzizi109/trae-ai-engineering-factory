<#
.SYNOPSIS
Initializes a new repository created from this factory baseline.

.DESCRIPTION
Updates the project-facing identity in README.md and .trae/current-project-state.md
from the repository root inferred from this script location. Supports a check-only
mode that reports the planned changes without modifying any files.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter()]
    [string]$ProjectSummary = '',

    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Resolves the repository root from the script path.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return $projectRoot
}

function Get-RequiredRelativePaths {
    <#
    .SYNOPSIS
    Returns the files that must exist before initialization.
    #>
    [OutputType([string[]])]
    param()

    return @(
        'README.md'
        '.trae/current-project-state.md'
    )
}

function Assert-RequiredFiles {
    <#
    .SYNOPSIS
    Ensures the required files exist before any update is attempted.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $missingFiles = New-Object System.Collections.Generic.List[string]

    foreach ($relativePath in Get-RequiredRelativePaths) {
        $fullPath = Join-Path -Path $ProjectRoot -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missingFiles.Add($relativePath)
        }
    }

    if ($missingFiles.Count -gt 0) {
        $missingList = ($missingFiles | ForEach-Object { "- $_" }) -join [Environment]::NewLine
        throw "Initialization cannot continue. Missing required files:$([Environment]::NewLine)$missingList"
    }
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

function Invoke-Initialization {
    <#
    .SYNOPSIS
    Applies or previews the tracked project identity updates.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter(Mandatory = $true)]
        [string]$ProjectSummary,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $readmePath = Join-Path -Path $ProjectRoot -ChildPath 'README.md'
    $projectStatePath = Join-Path -Path $ProjectRoot -ChildPath '.trae/current-project-state.md'

    $readmeContent = Get-Content -LiteralPath $readmePath -Raw
    $projectStateContent = Get-Content -LiteralPath $projectStatePath -Raw

    $updatedProjectStateContent = Get-UpdatedProjectStateContent -Content $projectStateContent -ProjectName $ProjectName -ProjectSummary $ProjectSummary
    $readmeSupportsIdentityUpdate = Test-ReadmeSupportsFactoryIdentityUpdate -Content $readmeContent
    $updatedReadmeContent = $readmeContent
    $readmeChanged = $false
    if ($readmeSupportsIdentityUpdate) {
        $updatedReadmeContent = Get-UpdatedReadmeContent -Content $readmeContent -ProjectName $ProjectName -ProjectSummary $ProjectSummary
        $readmeChanged = (Get-NormalizedComparableText -Content $updatedReadmeContent) -cne (Get-NormalizedComparableText -Content $readmeContent)
    }
    $projectStateChanged = (Get-NormalizedComparableText -Content $updatedProjectStateContent) -cne (Get-NormalizedComparableText -Content $projectStateContent)

    if ($IsCheckOnly) {
        Write-Host 'Check-only mode: no files will be modified.'
        if (-not $readmeSupportsIdentityUpdate) {
            Write-Host 'README.md uses a project-specific structure; skipping README identity update.'
        }
        elseif ($readmeChanged) {
            Write-Host "Would update README.md with project title '$ProjectName' and summary '$ProjectSummary'."
        }
        else {
            Write-Host 'README.md is already aligned with the requested project identity.'
        }

        if ($projectStateChanged) {
            Write-Host "Would update .trae/current-project-state.md with the Project Identity section for '$ProjectName'."
        }
        else {
            Write-Host '.trae/current-project-state.md already contains the requested Project Identity section.'
        }

        return
    }

    if ($readmeSupportsIdentityUpdate -and $readmeChanged) {
        Write-Utf8File -Path $readmePath -Content $updatedReadmeContent
    }

    if ($projectStateChanged) {
        Write-Utf8File -Path $projectStatePath -Content $updatedProjectStateContent
    }

    Write-Host 'Project initialization completed successfully.'
    if (-not $readmeSupportsIdentityUpdate) {
        Write-Host 'README.md updated: skipped (project-specific README structure)'
    }
    else {
        Write-Host "README.md updated: $readmeChanged"
    }
    Write-Host ".trae/current-project-state.md updated: $projectStateChanged"
}

function Main {
    <#
    .SYNOPSIS
    Validates inputs and runs the project initializer.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ProjectSummary,

        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $trimmedProjectName = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedProjectName)) {
        throw 'ProjectName must contain at least one non-whitespace character.'
    }

    $projectRoot = Get-ProjectRoot
    Assert-RequiredFiles -ProjectRoot $projectRoot

    $effectiveSummary = Get-EffectiveProjectSummary -Summary $ProjectSummary
    Invoke-Initialization -ProjectRoot $projectRoot -ProjectName $trimmedProjectName -ProjectSummary $effectiveSummary -IsCheckOnly $IsCheckOnly
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Main -ProjectName $ProjectName -ProjectSummary $ProjectSummary -IsCheckOnly $CheckOnly.IsPresent
    }
    catch {
        Write-Error $_
        exit 1
    }
}
