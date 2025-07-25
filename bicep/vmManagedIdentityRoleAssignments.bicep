targetScope = 'subscription'
import * as exports from './exports.bicep'

param principalId string
param roles array

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [ for role in roles: {
  name: guid(subscription().id, principalId, exports.role_lookup[role])
  properties: {
    roleDefinitionId: exports.role_lookup[role]
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]
