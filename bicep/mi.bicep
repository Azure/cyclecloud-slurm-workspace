targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param storageAccountName string
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

output managedIdentityId string = managedIdentity.id
