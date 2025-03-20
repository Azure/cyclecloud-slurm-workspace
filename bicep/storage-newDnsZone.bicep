targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param storageAccountId string
param vnetResourceGroup string
param vnetName string
param tags tags_t

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
      id: resourceId(vnetResourceGroup,'Microsoft.Network/virtualNetworks', vnetName)
    }
  }
}

output blobPrivateDnsZoneId string = blobPrivateDnsZone.id
