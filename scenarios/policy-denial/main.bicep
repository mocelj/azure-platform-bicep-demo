targetScope = 'resourceGroup'

@description('Existing plan from the compliant deployment. This fixture is for validation only.')
param serverFarmResourceId string
param name string

// Deliberately bypass the platform wrapper to demonstrate Azure-side enforcement.
// The workflow validates this template; it never deploys it.
module noncompliantSite 'br/public:avm/res/web/site:0.24.0' = {
  name: 'validate-public-access-policy'
  params: {
    name: name
    location: 'swedencentral'
    kind: 'app,linux'
    reserved: true
    serverFarmResourceId: serverFarmResourceId
    publicNetworkAccess: 'Enabled'
    httpsOnly: true
    enableTelemetry: false
    basicPublishingCredentialsPolicies: [
      { name: 'ftp', allow: false }
      { name: 'scm', allow: false }
    ]
    siteConfig: {
      linuxFxVersion: 'NODE|24-lts'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
    tags: {
      purpose: 'policy-validation-only'
    }
  }
}
