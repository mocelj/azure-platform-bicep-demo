#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$RepoRoot = Split-Path $PSScriptRoot -Parent
$OutputRoot = Join-Path $RepoRoot 'out'
$Bicep = Join-Path $RepoRoot $(if ($IsWindows) { '.tools/bicep.exe' } else { '.tools/bicep' })
$PolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/1b5ef780-c53c-4a64-87f3-bb9c8c8094ba'
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

function Invoke-Bicep {
    param([string[]]$Arguments)
    & $Bicep @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Bicep command failed.' }
}
function Get-Json {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
}
function Write-Json {
    param([string]$Path, $Value)
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 100) + "`n", [Text.UTF8Encoding]::new($false))
}
function Get-FileDigest {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function ConvertTo-CanonicalValue {
    param([AllowNull()]$Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [System.Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-CanonicalValue $Value[$key] }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $result.Add((ConvertTo-CanonicalValue $item)) }
        return ,($result.ToArray())
    }
    return $Value
}
function Get-JsonDigest {
    param($Value)
    $json = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $Value) -Depth 100 -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
}
function Get-WhatIfSummary {
    param($Result, [string]$ResourceGroupId)
    if ($Result.status -ne 'Succeeded' -or -not $Result.Contains('changes')) { throw 'What-if did not return a complete result.' }
    $counts = @{}
    $changes = @($Result.changes | Sort-Object resourceId)
    foreach ($change in $changes) {
        if ($change.changeType -notin @('Create', 'Modify', 'NoChange')) { throw "What-if requires further review: $($change.changeType). Apply is blocked." }
        if (-not $change.resourceId.StartsWith("$ResourceGroupId/", [StringComparison]::OrdinalIgnoreCase)) { throw 'What-if contains a change outside the workload group.' }
        $counts[$change.changeType] = 1 + [int]$counts[$change.changeType]
    }
    return @{ counts = $counts; digest = Get-JsonDigest $changes }
}
function Test-ExpectedPolicyDenial {
    param([int]$ExitCode, [string]$Message, [string]$AssignmentId)
    if ($ExitCode -eq 0) { throw 'The noncompliant template passed validation. Policy enforcement has not been demonstrated.' }
    if ($Message -notmatch 'RequestDisallowedByPolicy' -or
        -not $Message.Contains($PolicyDefinitionId, [StringComparison]::OrdinalIgnoreCase) -or
        -not $Message.Contains($AssignmentId, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Validation failed for a reason other than the expected demo policy.'
    }
}
