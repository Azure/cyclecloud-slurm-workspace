targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param storageAccountName string
param monitoringEnabled bool 
param dcrId string 
param tags tags_t

//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

module ccwMIRoleAssignments './miRoleAssignments.bicep' = {
  name: 'ccwRoleForLockerManagedIdentity'
  params: {
    principalId: managedIdentity.properties.principalId
    roles: ['Storage Blob Data Reader']
    storageAccountName: storageAccountName
  }
}

module ccwMIMonitoringRoleAssignment './miMonitoringRoleAssignments.bicep' = if (monitoringEnabled) {
  name: 'ccwMonitoringRoleForLockerManagedIdentity'
  scope : resourceGroup(split(dcrId, '/')[4])
  params: {
    principalId: managedIdentity.properties.principalId
    dcrId: dcrId
  }
}

output managedIdentityId string = managedIdentity.id
output managedIdentityClientId string = managedIdentity.properties.clientId
