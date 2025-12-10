targetScope = 'resourceGroup'
import * as exports from './exports.bicep'

param principalId string
param dcrId string

resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' existing = {
  name: split(dcrId, '/')[8]
}

var monitoringMetricsPublisher = 'Monitoring Metrics Publisher'
resource roleAssignmentsMnitoring 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, exports.role_lookup[monitoringMetricsPublisher])
  scope: dcr
  properties: {
    roleDefinitionId: exports.role_lookup[monitoringMetricsPublisher]
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
