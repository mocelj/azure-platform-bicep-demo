using './main.bicep'

// Local compilation example only. This file does not authorize an Azure deployment.
param namePrefix = 'platform-bicep-demo'
param location = 'swedencentral'
param sharedResourceGroupName = 'rg-platform-bicep-demo-shared'
param appResourceGroupName = 'rg-platform-bicep-demo-app'
param repository = 'mocelj/azure-platform-bicep-demo'
param availabilityZone = 1
