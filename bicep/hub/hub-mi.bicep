targetScope = 'resourceGroup'
import {tags_t} from '.././types.bicep'
import * as exports from './exports.bicep'

param name string = '{resourceGroup().name}-mi'
param location string = resourceGroup().location
param tags tags_t = {}

//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

var roles = [
    'Storage Blob Data Reader'
    'Storage Blob Data Constributor'
    'Monitoring Metrics Publisher'
  ]

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [ for role in roles: {
  name: guid(subscription().id, principalId, exports.role_lookup[role])
  scope: storageAccount
  properties: {
    roleDefinitionId: exports.role_lookup[role]
    
    principalType: 'ResourceGroup'
  }
}]

output hubMI string = managedIdentity.id
