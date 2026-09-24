targetScope = 'resourceGroup'

@description('Platform-owned lower-case resource prefix.')
@minLength(3)
@maxLength(24)
param namePrefix string

@allowed(['swedencentral'])
param location string

@description('Exact owner/repository; no branch, pull-request, fork wildcard or arbitrary OIDC subject.')
param repository string

@allowed([1, 2, 3])
param availabilityZone int

var repositoryParts = split(repository, '/')
var checkedRepository = length(repositoryParts) == 2 && !empty(repositoryParts[?0]) && !empty(repositoryParts[?1]) && !contains(repository, ':') && !contains(repository, '*') && !contains(repository, '?') && !contains(repository, ' ')
  ? repository
  : fail('repository must be an exact owner/repository, without a subject suffix or wildcard.')
var tags = {
  purpose: 'platform-native-bicep-demo'
  environment: 'demo'
}
var vnetName = 'vnet-${namePrefix}'

module deploymentIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: '${namePrefix}-identity'
  params: {
    name: 'id-${namePrefix}-deploy'
    location: location
    tags: tags
    federatedIdentityCredentials: [for phase in ['plan', 'apply']: {
      name: 'github-demo-${phase}'
      issuer: 'https://token.actions.githubusercontent.com'
      audiences: ['api://AzureADTokenExchange']
      subject: 'repo:${checkedRepository}:environment:demo-${phase}'
    }]
    enableTelemetry: false
  }
}

module sharedReader 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: '${namePrefix}-shared-reader'
  params: {
    principalId: deploymentIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Reader'
    description: 'Discover shared network, DNS and monitoring metadata; no identity modification or shared-resource provisioning.'
    enableTelemetry: false
  }
}

var subnetRoles = [{
  principalId: deploymentIdentity.outputs.principalId
  principalType: 'ServicePrincipal'
  roleDefinitionIdOrName: 'Network Contributor'
}]

module integrationNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: '${namePrefix}-integration-nsg'
  params: {
    name: 'nsg-${namePrefix}-web-app'
    location: location
    tags: tags
    securityRules: [{
      name: 'DenyInboundToIntegration'
      properties: {
        priority: 100
        access: 'Deny'
        direction: 'Inbound'
        protocol: '*'
        sourceAddressPrefix: '*'
        sourcePortRange: '*'
        destinationAddressPrefix: '*'
        destinationPortRange: '*'
      }
    }]
    enableTelemetry: false
  }
}

module outboundPublicIp 'br/public:avm/res/network/public-ip-address:0.13.0' = {
  name: '${namePrefix}-outbound-pip'
  params: {
    name: 'pip-${namePrefix}-outbound'
    location: location
    skuName: 'Standard'
    skuTier: 'Regional'
    availabilityZones: [availabilityZone]
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    tags: tags
    enableTelemetry: false
  }
}

module nat 'br/public:avm/res/network/nat-gateway:2.1.1' = {
  name: '${namePrefix}-nat'
  params: {
    name: 'nat-${namePrefix}'
    location: location
    natGatewaySku: 'Standard'
    availabilityZone: availabilityZone
    idleTimeoutInMinutes: 10
    publicIpResourceIds: [outboundPublicIp.outputs.resourceId]
    tags: tags
    enableTelemetry: false
  }
}

module network 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: '${namePrefix}-network'
  params: {
    name: vnetName
    location: location
    addressPrefixes: ['10.62.0.0/16']
    tags: tags
    subnets: [
      {
        name: 'snet-private-endpoints'
        addressPrefix: '10.62.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
        roleAssignments: subnetRoles
      }
      {
        name: 'snet-web-app'
        addressPrefix: '10.62.2.0/24'
        delegation: 'Microsoft.Web/serverFarms'
        networkSecurityGroupResourceId: integrationNsg.outputs.resourceId
        natGatewayResourceId: nat.outputs.resourceId
        defaultOutboundAccess: false
        roleAssignments: subnetRoles
      }
    ]
    enableTelemetry: false
  }
}

module privateDns 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: '${namePrefix}-private-dns'
  params: {
    name: 'privatelink.azurewebsites.net'
    location: 'global'
    tags: tags
    virtualNetworkLinks: [{
      name: '${vnetName}-link'
      virtualNetworkResourceId: network.outputs.resourceId
      registrationEnabled: false
    }]
    roleAssignments: [{
      principalId: deploymentIdentity.outputs.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionIdOrName: 'Private DNS Zone Contributor'
    }]
    enableTelemetry: false
  }
}

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: '${namePrefix}-workspace'
  params: {
    name: 'log-${namePrefix}'
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    forceCmkForQuery: false
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    tags: tags
    enableTelemetry: false
  }
}

output deploymentClientId string = deploymentIdentity.outputs.clientId
output deploymentPrincipalId string = deploymentIdentity.outputs.principalId
output deploymentIdentityResourceId string = deploymentIdentity.outputs.resourceId
output logAnalyticsWorkspaceResourceId string = workspace.outputs.resourceId
output privateEndpointSubnetResourceId string = network.outputs.subnetResourceIds[0]
output integrationSubnetResourceId string = network.outputs.subnetResourceIds[1]
output privateDnsZoneResourceId string = privateDns.outputs.resourceId
