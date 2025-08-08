targetScope = 'resourceGroup'
import {tags_t} from '.././types.bicep'
import * as exports from '.././exports.bicep'

param name string = '${resourceGroup().name}-mi'
param location string = resourceGroup().location
param dcrResourceGroup string 
param tags tags_t = {}

//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

var roles = [
    'Storage Blob Data Reader'
    'Storage Blob Data Contributor'
  ]

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [ for role in roles: {
  name: guid(subscription().id, managedIdentity.id, exports.role_lookup[role])
  scope: resourceGroup()
  properties: {
    roleDefinitionId: exports.role_lookup[role]
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

module dcrMIRoleAssignments './hub-mi-dcr.bicep' = {
  name: 'roleForMonitoringDCR'
  scope: resourceGroup(dcrResourceGroup)
  params: {
    miPrincipalId: managedIdentity.properties.principalId
    miId: managedIdentity.id
  }
  dependsOn: [
    roleAssignments
  ]
}

output hubMI string = managedIdentity.id
output hubMIClientId string = managedIdentity.properties.clientId
