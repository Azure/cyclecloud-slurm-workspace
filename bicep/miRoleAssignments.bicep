targetScope = 'resourceGroup'
import * as exports from './exports.bicep'

param principalId string
param roles array
param storageAccountName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' existing = {
  name: storageAccountName
}

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [ for role in roles: {
  name: guid(subscription().id, principalId, exports.role_lookup[role])
  scope: storageAccount
  properties: {
    roleDefinitionId: exports.role_lookup[role]
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]
