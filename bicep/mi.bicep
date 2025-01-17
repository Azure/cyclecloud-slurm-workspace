targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param tags tags_t

//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output managedIdentityId string = managedIdentity.id
output principalId string = managedIdentity.properties.principalId
