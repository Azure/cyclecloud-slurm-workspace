targetScope = 'resourceGroup'

param location string
param userObjectId string

var uniqueId = uniqueString(az.resourceGroup().id)

module managedMonitoring 'managedMonitoring.bicep' = {
  name: 'managedMonitoring'
  params: {
    location: location
    monitorName: 'ccw-mon-${uniqueId}'
    grafanaName: 'ccw-graf-${uniqueId}'
    umiName: 'ccw-mon-umi-${uniqueId}'
    principalUserId: userObjectId
  }
}

output managedIdentityclientId string = managedMonitoring.outputs.managedIdentityclientId
output ingestionEndpoint string = managedMonitoring.outputs.metricsIngestionEndpoint
output managedIdentityPrincipalId string = managedMonitoring.outputs.managedIdentityPrincipalId
output dcrResourceId string = managedMonitoring.outputs.dcrResourceId
