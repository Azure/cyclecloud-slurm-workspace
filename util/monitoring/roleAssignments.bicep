// Assign the Monitoring Metrics Publisher role to the User-Managed Identity, scoped to the Data Collection Rule of the monitor workspace
param dcrResourceId string

param principalId string

var roleDefinitionIds = {
  GrafanaAdmin: '22926164-76b3-42b3-bc55-97df8dab3e41'
  MonitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
  MonitoringDataReader: 'b0d8363b-8ddd-447d-831f-62ca05bff136'
}

var dcrName = split(dcrResourceId, '/')[8]
var dcrRg = split(dcrResourceId, '/')[4]

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' existing = {
  name: dcrName
  scope: resourceGroup(dcrRg)
}

// This generate this error when trying to uncomment the scope. How to set this correctly?
// A resource's scope must match the scope of the Bicep file for it to be deployable. You must use modules to deploy resources to a different scope.bicep BCP139
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionIds.MonitoringMetricsPublisher)
    principalId: principalId
  }
//  scope: dataCollectionRule
}
