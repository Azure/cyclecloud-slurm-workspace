extension microsoftGraphV1
targetScope = 'resourceGroup'

@description('User Managed Identity Name for Open OnDemand')
param miName string

// Creates a secret-less client application, using a user-assigned managed identity
// as the credential (configured as part of the application's federated identity credential).

@description('EntraID Application Name')
param name string
@description('FQDN, public or private IP of the OOD VM')
param fqdn string

module oodApp '../../bicep/oodEntraApp.bicep' = {
  name: 'oodApp'
  params: {
    umiName: miName
    appName: name
    fqdn: fqdn
  }
}

