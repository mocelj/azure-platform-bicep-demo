using './main.bicep'

// Compilation fixture only. These resources do not exist.
param name = 'ledger-native'
param size = 'small'
param logAnalyticsWorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-validation/providers/Microsoft.OperationalInsights/workspaces/log-validation'
param privateEndpointSubnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-validation/providers/Microsoft.Network/virtualNetworks/vnet-validation/subnets/endpoints'
param privateDnsZoneResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-validation/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net'
param integrationSubnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-validation/providers/Microsoft.Network/virtualNetworks/vnet-validation/subnets/integration'
