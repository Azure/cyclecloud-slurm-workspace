targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param resourceId string
param subnetId string
param privateDnsZoneName string
param tags tags_t

var virtualNetworkResourceGroup = split(subnetId, '/')[4]
var virtualNetworkName = split(subnetId, '/')[8]

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: privateDnsZoneName

  resource privateDnsZoneVnetLink 'virtualNetworkLinks@2024-06-01' = {
    name: 'vnetLink-${uniqueString(resourceId)}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: az.resourceId(virtualNetworkResourceGroup,'Microsoft.Network/virtualNetworks', virtualNetworkName)
      }
    }
  }
}
