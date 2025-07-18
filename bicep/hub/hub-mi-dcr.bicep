targetScope = 'resourceGroup'
import * as exports from '.././exports.bicep'

param miPrincipalId string
param miId string 

var role = 'Monitoring Metrics Publisher'
resource roleAssignments_dcr 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, miId, exports.role_lookup[role])
  properties: {
    roleDefinitionId: exports.role_lookup[role]
    principalId: miPrincipalId
    principalType: 'ServicePrincipal'
  }
}
