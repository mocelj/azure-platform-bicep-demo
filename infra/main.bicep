targetScope = 'resourceGroup'

@minLength(3)
@maxLength(20)
param name string
@allowed(['small', 'medium'])
param size string
param logAnalyticsWorkspaceResourceId string
param privateEndpointSubnetResourceId string
param privateDnsZoneResourceId string
param integrationSubnetResourceId string

module webApp '../.platform/platform-apps/web-app/bicep/main.bicep' = {
  name: 'platform-web-app'
  params: {
    name: name
    size: size
    location: 'swedencentral'
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceResourceId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
    privateDnsZoneResourceId: privateDnsZoneResourceId
    integrationSubnetResourceId: integrationSubnetResourceId
    tags: {
      purpose: 'platform-native-bicep-demo'
    }
  }
}

output resourceId string = webApp.outputs.resourceId
output resourceName string = webApp.outputs.resourceName
