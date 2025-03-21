targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param storageAccountId string
param subnetId string
param tags tags_t

var virtualNetworkResourceGroup = split(subnetId, '/')[4]
var virtualNetworkName = split(subnetId, '/')[8]

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: name
  location: 'global'
  tags: tags
}

resource blobPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobPrivateDnsZone
  name: uniqueString(storageAccountId)
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId(virtualNetworkResourceGroup,'Microsoft.Network/virtualNetworks', virtualNetworkName)
    }
  }
}

output blobPrivateDnsZoneId string = blobPrivateDnsZone.id
