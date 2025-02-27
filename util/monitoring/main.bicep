targetScope = 'resourceGroup'

param location string

var uniqueId = uniqueString(az.resourceGroup().id)

module managedMonitoring 'managedMonitoring.bicep' = {
  name: 'managedMonitoring'
  params: {
    location: location
    monitorName: 'ccw-mon-${uniqueId}'
    grafanaName: 'ccw-graf-${uniqueId}'
    umiName: 'ccw-mon-umi-${uniqueId}'
  }
}

output maganagedIdentityclientId string = managedMonitoring.outputs.maganagedIdentityclientId
output ingestionEndpoint string = managedMonitoring.outputs.metricsIngestionEndpoint
