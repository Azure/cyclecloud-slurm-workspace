targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param storageAccountName string
param applyRoleAssignments bool = true
param monitoringEnabled bool = false
param dcrId string = 'a0a0a0a0/bbbb/cccc/dddd/eeee/ffff/aaaa/bbbb/c8c8c8c8'
param tags tags_t = {}

//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

module ccwLockerManagedIdentityRoleAssignments './lockerManagedIdentityRoleAssignments.bicep' = if (applyRoleAssignments) {
  name: 'ccwRoleForLockerManagedIdentity'
  params: {
    principalId: managedIdentity.properties.principalId
    roles: ['Storage Blob Data Reader']
    storageAccountName: storageAccountName
  }
}

module ccwMIMonitoringRoleAssignment './miMonitoringRoleAssignments.bicep' = if (applyRoleAssignments && monitoringEnabled) {
  name: 'ccwMonitoringRoleForLockerManagedIdentity'
  scope : resourceGroup(split(dcrId, '/')[4])
  params: {
    principalId: managedIdentity.properties.principalId
    dcrId: dcrId
  }
}

output managedIdentityId string = managedIdentity.id
output managedIdentityClientId string = managedIdentity.properties.clientId
