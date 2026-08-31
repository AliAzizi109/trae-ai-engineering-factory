<#
.SYNOPSIS
Selects the preferred or next fallback model for a factory role.

.DESCRIPTION
Reads `.trae/factory/config/model-routing.json`, skips any failed models passed
through `-FailedModel`, and prints a JSON payload that explains the selection,
remaining candidates, and the next fallback candidate if the chosen model fails.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Role,

    [Parameter()]
    [Alias('FailedModels')]
    [AllowEmptyCollection()]
    [string[]]$FailedModel = @()
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

function Read-JsonHashtable {
    <#
    .SYNOPSIS
    Reads a JSON file as a hashtable.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "JSON file is empty: $Path"
    }

    try {
        return [hashtable](ConvertTo-HashtableObject -Value ($content | ConvertFrom-Json -ErrorAction Stop))
    }
    catch {
        throw "Failed to parse JSON file '$Path': $($_.Exception.Message)"
    }
}

function Get-SelectionReason {
    <#
    .SYNOPSIS
    Builds a concise explanation for why a model was selected.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedModel,

        [Parameter(Mandatory = $true)]
        [string]$PreferredModel,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$FailedModels
    )

    if ($SelectedModel -eq $PreferredModel) {
        return 'Preferred model selected because it is not listed in failed_models.'
    }

    if ($FailedModels.Count -eq 0) {
        return 'Fallback model selected based on the tracked routing order.'
    }

    return "Fallback model selected after excluding failed candidates: $($FailedModels -join ', ')"
}

function Main {
    <#
    .SYNOPSIS
    Selects a model for the requested role.
    #>
    [OutputType([void])]
    param()

    $projectRoot = Get-ProjectRoot
    $routingPath = Join-Path -Path $projectRoot -ChildPath '.trae\factory\config\model-routing.json'
    $routing = Read-JsonHashtable -Path $routingPath

    if ($null -eq $routing.role_routes -or $null -eq $routing.role_routes[$Role]) {
        throw "Role '$Role' is not defined in model-routing.json."
    }

    $roleRoute = [hashtable]$routing.role_routes[$Role]
    $preferredModel = [string]$roleRoute.preferred_model
    $fallbackModels = @($roleRoute.fallback_models | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    $failedModels = @($FailedModel | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    $candidates = @($preferredModel) + $fallbackModels
    $selectedModel = $null
    $selectedIndex = -1

    for ($index = 0; $index -lt $candidates.Count; $index++) {
        if ($failedModels -notcontains $candidates[$index]) {
            $selectedModel = $candidates[$index]
            $selectedIndex = $index
            break
        }
    }

    $remainingCandidates = @()
    $nextModelIfSelectedFails = $null
    if ($selectedIndex -ge 0) {
        if ($selectedIndex -lt ($candidates.Count - 1)) {
            $remainingCandidates = @($candidates[($selectedIndex + 1)..($candidates.Count - 1)] | Where-Object { $failedModels -notcontains $_ })
            if ($remainingCandidates.Count -gt 0) {
                $nextModelIfSelectedFails = [string]$remainingCandidates[0]
            }
        }
    }

    $selectionReason = if ($null -eq $selectedModel) {
        'No model selected because all configured candidates are listed in failed_models.'
    }
    else {
        Get-SelectionReason -SelectedModel $selectedModel -PreferredModel $preferredModel -FailedModels $failedModels
    }

    $result = [ordered]@{
        role = $Role
        preferred_model = $preferredModel
        fallback_models = $fallbackModels
        failed_models = $failedModels
        selected_model = $selectedModel
        selection_index = $selectedIndex
        remaining_candidates = $remainingCandidates
        next_model_if_selected_fails = $nextModelIfSelectedFails
        fallback_used = ($null -ne $selectedModel -and $selectedModel -ne $preferredModel)
        exhausted = ($null -eq $selectedModel)
        selection_reason = $selectionReason
        operator_summary = if ($null -eq $selectedModel) {
            "No selectable model remains for role '$Role'."
        }
        elseif ($selectedModel -eq $preferredModel) {
            "Role '$Role' stays on preferred model '$selectedModel'."
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$nextModelIfSelectedFails)) {
            "Role '$Role' falls back to '$selectedModel'; no further fallback is available."
        }
        else {
            "Role '$Role' falls back to '$selectedModel'; next fallback is '$nextModelIfSelectedFails'."
        }
        selection_contract = if ($null -ne $routing.selection_contract.mode) {
            [string]$routing.selection_contract.mode
        }
        else {
            'orchestrator_managed_phase_contract'
        }
        truthfulness_note = if ($null -ne $routing.selection_contract.truthfulness_note) {
            [string]$routing.selection_contract.truthfulness_note
        }
        else {
            'Repository routing intent only; this output does not prove runtime model availability or native repo-agent callability.'
        }
    }

    Write-Output ($result | ConvertTo-Json -Depth 10)
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
