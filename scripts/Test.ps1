#requires -Version 7.4
[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
& (Join-Path $PSScriptRoot 'Build.ps1') -ValidationOnly
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
$revision = (Get-Content (Join-Path $RepoRoot 'platform.ref') -Raw).Trim()
Assert ($revision -cmatch '^[0-9a-f]{40}$') 'Catalog pin must be a full SHA.'
$main = Get-Content (Join-Path $RepoRoot 'infra/main.bicep') -Raw
Assert ($main.Contains("../.platform/platform-apps/web-app/bicep/main.bicep")) 'Use the checked-out platform wrapper.'
$sources = @(Get-ChildItem (Join-Path $RepoRoot 'infra'), (Join-Path $RepoRoot 'platform-setup'), (Join-Path $RepoRoot 'scenarios') -Recurse -Filter *.bicep)
foreach ($file in $sources) {
    $text = Get-Content $file.FullName -Raw
    Assert ($text -notmatch '(?m)^\s*resource\s') "First-party base resources are not allowed: $($file.Name)."
    foreach ($match in [regex]::Matches($text, "br/public:([^']+)")) {
        Assert ($match.Groups[1].Value -match '^avm/(res|utl)/[a-z0-9/-]+:\d+\.\d+\.\d+$') 'Unpinned or non-AVM module reference.'
    }
    Assert ($text -notmatch ':latest\b|enableTelemetry:\s*true') 'Floating references or enabled AVM telemetry found.'
}
$setup = ($sources | Where-Object FullName -Like '*platform-setup*' | ForEach-Object {Get-Content $_.FullName -Raw}) -join "`n"
foreach ($required in @($PolicyDefinitionId,"definitionVersion: '1.2.0'","enforcementMode: 'Default'","value: 'Deny'","managedIdentities: {}")) {
    Assert ($setup.Contains($required)) "Missing platform guardrail: $required"
}
Assert ($setup.Contains("for phase in ['plan', 'apply']") -and $setup.Contains(':environment:demo-${phase}')) 'Both environment federation subjects are required.'
Assert ($setup -notmatch "roleDefinitionIdOrName: '(Owner|User Access Administrator|Resource Policy Contributor)'") 'App identity must not manage governance.'
$negative = Get-Content (Join-Path $RepoRoot 'scenarios/policy-denial/main.bicep') -Raw
Assert ($negative.Contains("publicNetworkAccess: 'Enabled'")) 'Negative fixture must reach policy evaluation.'
$cloud = Get-Content (Join-Path $RepoRoot 'scripts/Cloud.ps1') -Raw
Assert ($cloud.Contains('ENABLE_AZURE_DEPLOYMENT') -and $cloud.Contains("refs/heads/main")) 'Cloud execution gate missing.'
Assert ($cloud.Contains('--validation-level Provider')) 'Policy test must use provider validation.'
Assert ($cloud -notmatch "deployment group create.*policy-denial") 'Do not deploy the negative fixture.'
$params = Get-Json (Join-Path $OutputRoot 'demo-validation.parameters.json')
Assert ($params.parameters.size.value -in @('small','medium')) 'Invalid demo profile.'
Assert ($params.parameters.name.value -cmatch '^[a-z][a-z0-9-]{2,19}$') 'Invalid application name.'

$scope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test'
$good = @{ status = 'Succeeded'; changes = @(@{changeType='Create';resourceId="$scope/providers/Microsoft.Web/sites/test"}) }
Assert ((Get-WhatIfSummary $good $scope).counts.Create -eq 1) 'Valid what-if rejected.'
foreach ($change in @('Delete','Ignore','Unsupported','Deploy')) {
    Assert-Throws {Get-WhatIfSummary @{status='Succeeded';changes=@(@{changeType=$change;resourceId="$scope/providers/Microsoft.Web/sites/test"})} $scope} "Unsafe what-if accepted: $change."
}
Assert-Throws {Get-WhatIfSummary @{status='Succeeded';changes=@(@{changeType='Create';resourceId='/other/scope'})} $scope} 'Cross-scope change accepted.'
$assignment = "$scope/providers/Microsoft.Authorization/policyAssignments/deny-public"
Test-ExpectedPolicyDenial 1 "RequestDisallowedByPolicy $PolicyDefinitionId $assignment" $assignment
Assert-Throws {Test-ExpectedPolicyDenial 0 'allowed' $assignment} 'Allowed request treated as denied.'
Assert-Throws {Test-ExpectedPolicyDenial 1 'AuthorizationFailed' $assignment} 'RBAC failure treated as policy proof.'
Assert-Throws {Test-ExpectedPolicyDenial 1 "RequestDisallowedByPolicy $PolicyDefinitionId /wrong/assignment" $assignment} 'Wrong policy assignment accepted.'
Assert ((Get-JsonDigest @{a=1;b=@(2,3)}) -eq (Get-JsonDigest @{b=@(2,3);a=1})) 'JSON hashing depends on property order.'
Assert ((Get-JsonDigest @{a=@(2,3)}) -ne (Get-JsonDigest @{a=@(3,2)})) 'JSON hashing ignores array order.'
$oldEnabled = $env:ENABLE_AZURE_DEPLOYMENT
try {
    $env:ENABLE_AZURE_DEPLOYMENT = 'false'
    $blocked = $false
    try { & (Join-Path $PSScriptRoot 'Cloud.ps1') -Action Plan }
    catch { $blocked = $_.Exception.Message -like 'Azure execution requires*' }
    Assert $blocked 'Disabled cloud execution did not stop at the gate.'
} finally { $env:ENABLE_AZURE_DEPLOYMENT = $oldEnabled }

foreach ($file in Get-ChildItem (Join-Path $RepoRoot '.github/workflows') -Filter *.yml) {
    $text = Get-Content $file.FullName -Raw
    Assert ($text -notmatch 'pull_request_target|workflow_run|self-hosted|secrets: inherit') 'Unexpected privileged workflow path.'
    foreach ($match in [regex]::Matches($text,'uses:\s*([^\s#]+)')) {
        $action = $match.Groups[1].Value
        Assert ($action.StartsWith('./') -or $action -match '@[0-9a-f]{40}$') "Unpinned action: $action."
    }
}
$pr = Get-Content (Join-Path $RepoRoot '.github/workflows/validate.yml') -Raw
Assert ($pr -notmatch 'id-token:|azure/login|Cloud.ps1') 'PR validation must remain credential-free.'
Write-Host "Native demo checks passed: $($sources.Count) AVM-only Bicep sources, parameter builds, workflow boundaries and fail-closed plan/policy checks. No Azure calls were made."
