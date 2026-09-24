#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Plan', 'Apply', 'PolicyCheck')][string]$Action)
. (Join-Path $PSScriptRoot 'Common.ps1')

if ($env:ENABLE_AZURE_DEPLOYMENT -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'mocelj/azure-platform-bicep-demo' -or
    $env:GITHUB_REF -cne 'refs/heads/main' -or
    $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Azure execution requires an enabled, protected-main run in the demo repository.'
}
$head = (& git -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $env:GITHUB_SHA) { throw 'Checkout does not match the workflow commit.' }
$subscription = $env:AZURE_SUBSCRIPTION_ID
$group = $env:AZURE_RESOURCE_GROUP
if ($subscription -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or
    $subscription -eq '00000000-0000-0000-0000-000000000000' -or
    $group -notmatch '^rg-[a-z0-9-]{3,70}$') { throw 'A real subscription and workload resource group are required.' }
$groupId = "/subscriptions/$subscription/resourceGroups/$group"
$assignment = $env:PLATFORM_POLICY_ASSIGNMENT_ID
if ([string]::IsNullOrWhiteSpace($assignment) -or -not $assignment.StartsWith("$groupId/providers/Microsoft.Authorization/policyAssignments/", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The policy assignment must belong to this workload group.'
}
function Invoke-Azure {
    param([string[]]$Arguments)
    $raw = & az @Arguments --subscription $subscription --output json --only-show-errors 2> (Join-Path $OutputRoot 'azure-stderr.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Azure command failed. Inspect runner-local out/azure-stderr.txt; raw Azure output is not published.' }
    if ($raw) { return (($raw -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100) }
}
$cli = & az version --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $cli.'azure-cli' -ne '2.88.0') { throw 'Azure CLI 2.88.0 is required.' }
$account = Invoke-Azure @('account', 'show')
if ($account.id -ne $subscription) { throw 'Azure account context mismatch.' }
$policy = Invoke-Azure @('rest', '--method', 'get', '--url', "https://management.azure.com${assignment}?api-version=2025-03-01")
if ($policy.properties.policyDefinitionId -ne $PolicyDefinitionId -or
    $policy.properties.definitionVersion -ne '1.2.0' -or
    $policy.properties.parameters.effect.value -ne 'Deny' -or
    $policy.properties.enforcementMode -ne 'Default' -or
    @($policy.properties.notScopes | Where-Object { $_ }).Count -gt 0 -or
    @($policy.properties.overrides | Where-Object { $_ }).Count -gt 0 -or
    @($policy.properties.resourceSelectors | Where-Object { $_ }).Count -gt 0) {
    throw 'The expected versioned Deny policy is not configured without exclusions or overrides.'
}
foreach ($file in @('app.json','app.parameters.json','policy-denial.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $OutputRoot $file))) { throw 'Build the deployment inputs before Azure login.' }
}
$parameters = (Get-Json (Join-Path $OutputRoot 'app.parameters.json')).parameters
foreach ($key in @('logAnalyticsWorkspaceResourceId','privateEndpointSubnetResourceId','privateDnsZoneResourceId','integrationSubnetResourceId')) {
    if (-not $parameters[$key].value.StartsWith("/subscriptions/$subscription/", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid platform binding: $key."
    }
}
$templateHash = Get-FileDigest (Join-Path $OutputRoot 'app.json')
$parameterHash = Get-FileDigest (Join-Path $OutputRoot 'app.parameters.json')
$catalog = (Get-Content (Join-Path $RepoRoot 'platform.ref') -Raw).Trim()
$sourceHash = Get-JsonDigest @{ app = $head; catalog = $catalog; template = $templateHash; parameters = $parameterHash }
$deploymentArgs = @('--resource-group', $group, '--template-file', (Join-Path $OutputRoot 'app.json'),
    '--parameters', ('@' + (Join-Path $OutputRoot 'app.parameters.json')))

if ($Action -eq 'PolicyCheck') {
    $sites = @(Invoke-Azure @('webapp', 'list', '--resource-group', $group))
    if ($sites.Count -ne 1) { throw 'Deploy exactly one compliant Web App before the policy demonstration.' }
    $site = $sites[0]
    if ($site.publicNetworkAccess -ne 'Disabled') { throw 'The existing app is not private. Stop and investigate.' }
    $candidate = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{
            name = @{ value = "$($site.name)-policy-probe" }
            serverFarmResourceId = @{ value = $site.serverFarmId }
        }
    }
    Write-Json (Join-Path $OutputRoot 'policy-denial.parameters.json') $candidate
    $before = Invoke-Azure @('resource', 'list', '--resource-group', $group)
    $result = & az deployment group validate --subscription $subscription --resource-group $group `
        --template-file (Join-Path $OutputRoot 'policy-denial.json') `
        --parameters ('@' + (Join-Path $OutputRoot 'policy-denial.parameters.json')) `
        --validation-level Provider --output json --only-show-errors 2>&1
    $code = $LASTEXITCODE
    $message = $result -join "`n"
    [IO.File]::WriteAllText((Join-Path $OutputRoot 'policy-denial-result.txt'), $message)
    Test-ExpectedPolicyDenial -ExitCode $code -Message $message -AssignmentId $assignment
    $after = Invoke-Azure @('resource', 'list', '--resource-group', $group)
    if ((Get-JsonDigest @($before.id | Sort-Object)) -ne (Get-JsonDigest @($after.id | Sort-Object))) { throw 'Resource inventory changed during the validation check.' }
    $current = Invoke-Azure @('webapp', 'show', '--resource-group', $group, '--name', $site.name)
    if ($current.publicNetworkAccess -ne 'Disabled') { throw 'The existing app no longer reports public access disabled.' }
    $summary = "### Policy demonstration`nAzure rejected the validation request with **RequestDisallowedByPolicy** from the expected **1.2.0 Deny** assignment. The existing Web App remains private and the resource inventory is unchanged. No deployment was attempted."
} else {
    $whatIf = Invoke-Azure (@('deployment', 'group', 'what-if', '--no-pretty-print', '--validation-level', 'Provider') + $deploymentArgs)
    Write-Json (Join-Path $OutputRoot 'what-if.json') $whatIf
    $review = Get-WhatIfSummary -Result $whatIf -ResourceGroupId $groupId
    if ($Action -eq 'Plan') {
        if (-not $env:GITHUB_OUTPUT) { throw 'A GitHub job output path is required.' }
        Add-Content $env:GITHUB_OUTPUT "source_hash=$sourceHash"
        Add-Content $env:GITHUB_OUTPUT "change_hash=$($review.digest)"
        $summary = "### Infrastructure plan`nApp commit: $head`n`nCatalog commit: $catalog`n`nChanges: $($review.counts | ConvertTo-Json -Compress)`n`nRequested profile: $($parameters.size.value). Review the PR and this summary before approving demo-apply. This is infrastructure only; no application package is deployed."
    } else {
        if ($env:EXPECTED_SOURCE_HASH -cnotmatch '^[0-9a-f]{64}$' -or
            $env:EXPECTED_CHANGE_HASH -cnotmatch '^[0-9a-f]{64}$' -or
            $env:EXPECTED_SOURCE_HASH -ne $sourceHash -or
            $env:EXPECTED_CHANGE_HASH -ne $review.digest) {
            throw 'The reviewed source, inputs or Azure changes no longer match. Run a new plan and approval.'
        }
        $null = Invoke-Azure (@('deployment', 'group', 'create', '--name', "native-$($head.Substring(0,12))") + $deploymentArgs)
        $summary = "### Infrastructure deployment complete`nApplied the reviewed source and inputs. Verify App Service tier, private endpoint, public-access setting and diagnostics in Azure Portal. Application code and private HTTP health are outside this demo."
    }
}
Write-Host $summary
if ($env:GITHUB_STEP_SUMMARY) { Add-Content $env:GITHUB_STEP_SUMMARY $summary }
