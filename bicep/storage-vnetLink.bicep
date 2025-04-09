targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param storageAccountId string
param subnetId string
param blobPrivateDnsZoneName string
param tags tags_t

var virtualNetworkResourceGroup = split(subnetId, '/')[4]
var virtualNetworkName = split(subnetId, '/')[8]

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: blobPrivateDnsZoneName

  resource blobPrivateDnsZoneVnetLink 'virtualNetworkLinks@2020-06-01' = {
    name: 'vnetLink-${uniqueString(storageAccountId)}'
    location: 'global'
    tags: tags
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: resourceId(virtualNetworkResourceGroup,'Microsoft.Network/virtualNetworks', virtualNetworkName)
      }
    }
  }
}
