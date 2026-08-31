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
        $table = @{}
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
        $table = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-HashtableObject -Value $property.Value
        }
        return $table
    }

    return $Value
}

function Read-JsonHashtable {
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

function Get-FactoryPath {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $fullPath = Join-Path -Path $ProjectRoot -ChildPath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Required factory path not found: $fullPath"
    }

    return $fullPath
}

function Get-AllowedCreationPhases {
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$HandoffConfig
    )

    if (-not $HandoffConfig.ContainsKey('phase_sequence') -or $null -eq $HandoffConfig.phase_sequence) {
        throw 'Factory handoff config does not define phase_sequence.'
    }

    $allowedPhases = @($HandoffConfig.phase_sequence | ForEach-Object { [string]$_ } | Where-Object { $_ -notin @('intake', 'discovery') })
    if ($allowedPhases.Count -eq 0) {
        throw 'Factory handoff config does not define any task-creation phases.'
    }

    return $allowedPhases
}

function Assert-ConfigDefinedValue {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FieldName,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedValues,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$FieldName must not be empty."
    }

    if ($AllowedValues -notcontains $Value) {
        throw "$FieldName '$Value' is not defined in $SourcePath."
    }
}
