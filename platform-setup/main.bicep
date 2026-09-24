targetScope = 'subscription'

@description('Platform-owned naming prefix. Use lower-case letters, digits and hyphens.')
@minLength(3)
@maxLength(24)
param namePrefix string = 'platform-bicep-demo'

@allowed(['swedencentral'])
param location string = 'swedencentral'

@description('Dedicated demo foundation group; never target an existing customer foundation.')
@minLength(1)
@maxLength(90)
param sharedResourceGroupName string = 'rg-${namePrefix}-shared'

@description('Dedicated app group, separate from the shared foundation and deployment identity.')
@minLength(1)
@maxLength(90)
param appResourceGroupName string = 'rg-${namePrefix}-app'

@description('Exact owner/repository trusted by the two protected GitHub environments.')
param repository string = 'mocelj/azure-platform-bicep-demo'

@description('One matching logical zone for the Standard NAT gateway and its Standard outbound public IP. Live availability is not verified.')
@allowed([1, 2, 3])
param availabilityZone int = 1

var checkedAppResourceGroupName = toLower(sharedResourceGroupName) == toLower(appResourceGroupName)
  ? fail('Shared and application resource groups must be different.')
  : appResourceGroupName
var tags = {
  purpose: 'platform-native-bicep-demo'
  environment: 'demo'
}

module sharedGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${namePrefix}-shared-rg'
  params: {
    name: sharedResourceGroupName
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module appGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${namePrefix}-app-rg'
  params: {
    name: checkedAppResourceGroupName
    location: location
    tags: tags
    enableTelemetry: false
  }
}

module shared './shared.bicep' = {
  name: '${namePrefix}-shared'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    namePrefix: namePrefix
    location: location
    repository: repository
    availabilityZone: availabilityZone
  }
  dependsOn: [sharedGroup]
}

module denyPublicAppService 'br/public:avm/res/authorization/policy-assignment/rg-scope:0.1.0' = {
  name: '${namePrefix}-app-policy'
  scope: resourceGroup(checkedAppResourceGroupName)
  params: {
    name: 'deny-public-app-service'
    displayName: 'Demo App Service public network access must be disabled'
    description: 'Deny-only built-in guardrail for the dedicated application resource group.'
    location: location
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/1b5ef780-c53c-4a64-87f3-bb9c8c8094ba'
    definitionVersion: '1.2.0'
    parameters: {
      effect: {
        value: 'Deny'
      }
    }
    enforcementMode: 'Default'
    managedIdentities: {}
    metadata: tags
    nonComplianceMessages: [{
      message: 'App Service publicNetworkAccess must be explicitly Disabled. Use the platform private endpoint and separate VNet integration.'
    }]
    enableTelemetry: false
  }
  dependsOn: [appGroup]
}

module appContributor 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: '${namePrefix}-app-contributor'
  scope: resourceGroup(checkedAppResourceGroupName)
  params: {
    principalId: shared.outputs.deploymentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Contributor'
    description: 'Deploy app infrastructure only in the dedicated group; no policy or role-assignment administration.'
    enableTelemetry: false
  }
  // Install the guardrail before granting app deployment rights; allow for later policy/RBAC propagation.
  dependsOn: [denyPublicAppService]
}

output workloadResourceGroupName string = checkedAppResourceGroupName
output deploymentClientId string = shared.outputs.deploymentClientId
output deploymentPrincipalId string = shared.outputs.deploymentPrincipalId
output deploymentIdentityResourceId string = shared.outputs.deploymentIdentityResourceId
output logAnalyticsWorkspaceResourceId string = shared.outputs.logAnalyticsWorkspaceResourceId
output privateEndpointSubnetResourceId string = shared.outputs.privateEndpointSubnetResourceId
output integrationSubnetResourceId string = shared.outputs.integrationSubnetResourceId
output privateDnsZoneResourceId string = shared.outputs.privateDnsZoneResourceId
output policyAssignmentResourceId string = denyPublicAppService.outputs.resourceId
output tenantId string = tenant().tenantId
