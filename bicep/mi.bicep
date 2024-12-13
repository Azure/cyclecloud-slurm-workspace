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

var managedIdentityId = managedIdentity.id

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' existing = {
  name: storageAccountName
}

//assign Storage Blob Data Reader role to the managed identity scoped to CC storage account
resource miRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(name, managedIdentityId, resourceGroup().id, subscription().id)
  scope: storageAccount
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('microsoft.authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

output managedIdentityId string = managedIdentityId
