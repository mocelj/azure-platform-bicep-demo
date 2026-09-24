#requires -Version 7.4
[CmdletBinding()]
param([switch]$ValidationOnly)
. (Join-Path $PSScriptRoot 'Common.ps1')
& (Join-Path $PSScriptRoot 'Get-Bicep.ps1')
Invoke-Bicep @('build', (Join-Path $RepoRoot 'infra/main.bicep'), '--outfile', (Join-Path $OutputRoot 'app.json'))
if ($ValidationOnly) {
    $fixture = Join-Path $RepoRoot 'infra/validation.bicepparam'
    Invoke-Bicep @('build-params', $fixture, '--outfile', (Join-Path $OutputRoot 'validation.parameters.json'))
    $values = (Get-Json (Join-Path $OutputRoot 'validation.parameters.json')).parameters
    $bindings = @{
        PLATFORM_LOG_ANALYTICS_RESOURCE_ID = $values.logAnalyticsWorkspaceResourceId.value
        PLATFORM_PRIVATE_ENDPOINT_SUBNET_ID = $values.privateEndpointSubnetResourceId.value
        PLATFORM_PRIVATE_DNS_ZONE_ID = $values.privateDnsZoneResourceId.value
        PLATFORM_WEB_INTEGRATION_SUBNET_ID = $values.integrationSubnetResourceId.value
    }
    $previous = @{}
    try {
        foreach ($key in $bindings.Keys) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $bindings[$key])
        }
        Invoke-Bicep @('build-params', (Join-Path $RepoRoot 'infra/demo.bicepparam'), '--outfile', (Join-Path $OutputRoot 'demo-validation.parameters.json'))
    } finally {
        foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key]) }
    }
} else {
    Invoke-Bicep @('build-params', (Join-Path $RepoRoot 'infra/demo.bicepparam'), '--outfile', (Join-Path $OutputRoot 'app.parameters.json'))
}
Invoke-Bicep @('build', (Join-Path $RepoRoot 'scenarios/policy-denial/main.bicep'), '--outfile', (Join-Path $OutputRoot 'policy-denial.json'))
Invoke-Bicep @('build', (Join-Path $RepoRoot 'platform-setup/main.bicep'), '--outfile', (Join-Path $OutputRoot 'platform-setup.json'))
Invoke-Bicep @('build-params', (Join-Path $RepoRoot 'platform-setup/demo.bicepparam'), '--outfile', (Join-Path $OutputRoot 'platform-setup.parameters.json'))
Write-Host 'Bicep build complete. No Azure operation was performed.'
