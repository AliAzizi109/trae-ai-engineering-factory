<#
.SYNOPSIS
Validates the factory baseline and optionally bootstraps project-fs.

.DESCRIPTION
Checks that the tracked baseline files required for a new machine or cloned
project are present. When validation succeeds, the script either exits after a
success message in check-only mode or runs the project-fs bootstrap script.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    <#
    .SYNOPSIS
    Returns the repository root based on this script location.
    #>
    [OutputType([string])]
    param()

    $projectRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath $projectRoot -PathType Container)) {
        throw "Unable to resolve the project root from script path: $PSScriptRoot"
    }

    return $projectRoot
}

function Get-BaselineRelativePaths {
    <#
    .SYNOPSIS
    Returns the required baseline files for the factory bootstrap.
    #>
    [OutputType([string[]])]
    param()

    return @(
        'AGENTS.md'
        '.trae/agents/factory-reviewer.md'
        '.trae/agents/security-reviewer.md'
        '.trae/agents/qa-verifier.md'
        '.trae/rules/00-constitution.md'
        '.trae/agent-specs.md'
        '.trae/current-project-state.md'
        '.trae/factory/factory-system.md'
        '.trae/factory/verification-matrix.md'
        '.trae/factory/tasks/README.md'
        '.trae/factory/templates/task.md'
        '.trae/mcp.json'
        '.gitignore'
        'scripts/bootstrap-project-fs.ps1'
        'scripts/initialize-factory-project.ps1'
        'scripts/new-factory-task.ps1'
        'scripts/update-factory-task.ps1'
        '.trae-local/mcp/project-fs/package.json'
        '.trae-local/mcp/project-fs/package-lock.json'
    )
}

function Get-MissingBaselineFiles {
    <#
    .SYNOPSIS
    Returns any missing required baseline files.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $missingFiles = New-Object System.Collections.Generic.List[string]

    foreach ($relativePath in Get-BaselineRelativePaths) {
        $fullPath = Join-Path -Path $ProjectRoot -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missingFiles.Add($relativePath)
        }
    }

    return $missingFiles.ToArray()
}

function Assert-BaselineFiles {
    <#
    .SYNOPSIS
    Ensures all required baseline files exist before bootstrap continues.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $missingFiles = @(Get-MissingBaselineFiles -ProjectRoot $ProjectRoot)
    if ($missingFiles.Count -gt 0) {
        $missingList = ($missingFiles | ForEach-Object { "- $_" }) -join [Environment]::NewLine
        throw "Factory baseline validation failed. Missing files:$([Environment]::NewLine)$missingList"
    }
}

function Invoke-ProjectFsBootstrap {
    <#
    .SYNOPSIS
    Runs the tracked project-fs bootstrap script.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $bootstrapScriptPath = Join-Path -Path $ProjectRoot -ChildPath 'scripts\bootstrap-project-fs.ps1'
    if (-not (Test-Path -LiteralPath $bootstrapScriptPath -PathType Leaf)) {
        throw "Bootstrap script not found at: $bootstrapScriptPath"
    }

    & $bootstrapScriptPath
}

function Main {
    <#
    .SYNOPSIS
    Validates the baseline and optionally prepares the local project-fs setup.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$IsCheckOnly
    )

    $projectRoot = Get-ProjectRoot
    Assert-BaselineFiles -ProjectRoot $projectRoot

    if ($IsCheckOnly) {
        Write-Host 'Factory baseline check passed. All required files are present.'
        return
    }

    Invoke-ProjectFsBootstrap -ProjectRoot $projectRoot
    Write-Host 'Factory bootstrap completed successfully.'
    Write-Host 'Next steps:'
    Write-Host '1. Review git status.'
    Write-Host '2. Create a task record with scripts/new-factory-task.ps1 when you need persistent task state.'
    Write-Host '3. Resume or checkpoint that task with scripts/update-factory-task.ps1 as work progresses.'
    Write-Host '4. Commit/push the baseline or publish the template when ready.'
}

try {
    Main -IsCheckOnly $CheckOnly.IsPresent
}
catch {
    Write-Error $_
    exit 1
}
