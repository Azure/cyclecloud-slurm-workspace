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

var managedIdentityId = managedIdentity.id

//assign Storage Blob Data Contributor role to the managed identity
resource miRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(name, managedIdentityId, resourceGroup().id, subscription().id)
  scope: managedIdentity
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('microsoft.authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

output managedIdentityId string = managedIdentityId
