using './main.bicep'

param name = 'ledger-native'
param size = 'medium'

// The platform supplies these bindings through the protected GitHub environment.
param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('PLATFORM_LOG_ANALYTICS_RESOURCE_ID')
param privateEndpointSubnetResourceId = readEnvironmentVariable('PLATFORM_PRIVATE_ENDPOINT_SUBNET_ID')
param privateDnsZoneResourceId = readEnvironmentVariable('PLATFORM_PRIVATE_DNS_ZONE_ID')
param integrationSubnetResourceId = readEnvironmentVariable('PLATFORM_WEB_INTEGRATION_SUBNET_ID')
