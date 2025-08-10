targetScope = 'resourceGroup'
import {storagePrivateDnsZone_t,tags_t} from './types.bicep'

param location string
param tags tags_t
param saName string
param subnetId string
param storagePrivateDnsZone storagePrivateDnsZone_t

var privateDnsZoneId = storagePrivateDnsZone.?id ?? 'a0a0a0a0/bbbb/cccc/dddd/eeee/ffff/aaaa/bbbb/c8c8c8c8'
var privateDnsZoneResourceGroup = split(privateDnsZoneId, '/')[4]
var createVnetLink = storagePrivateDnsZone.type == 'existing' ? storagePrivateDnsZone.vnetLink : storagePrivateDnsZone.type == 'new'
var vnetLinkScope = contains(storagePrivateDnsZone,'id') ? split(privateDnsZoneId, '/')[4] : az.resourceGroup().name

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: saName
}

var storageBlobPrivateEndpointName = 'ccwstorage-blob-pe'

resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: storageBlobPrivateEndpointName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      { 
        name: storageBlobPrivateEndpointName
        properties: {
          groupIds: [
            'blob'
          ]
          privateLinkServiceId: storageAccount.id
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Auto-Approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
    customNetworkInterfaceName: '${storageBlobPrivateEndpointName}-nic'
    subnet: {
      id: subnetId
    }
  }
}

var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

module newBlobPrivateDnsZone 'storage-newDnsZone.bicep' = if (storagePrivateDnsZone.type == 'new') {
  name: 'ccwStorageNewDnsZone'
  params: {
    name: blobPrivateDnsZoneName
    tags: tags
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (storagePrivateDnsZone.type == 'existing') {
  name: blobPrivateDnsZoneName
  scope: resourceGroup(privateDnsZoneResourceGroup)
}

module blobPrivateDnsZoneVnetLink 'storage-vnetLink.bicep' = if (createVnetLink) {
  name: 'ccwStorageBlobPrivateDnsZoneVnetLink'
  scope: resourceGroup(vnetLinkScope)
  params: {
    storageAccountId: storageAccount.id
    subnetId: subnetId
    blobPrivateDnsZoneName: storagePrivateDnsZone.type == 'existing' ? blobPrivateDnsZone.name : newBlobPrivateDnsZone.outputs.blobPrivateDnsZoneName //force dependency
    tags: tags
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (storagePrivateDnsZone.type != 'none') {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: blobPrivateDnsZoneName
        properties:{
          privateDnsZoneId: storagePrivateDnsZone.type == 'existing' ? blobPrivateDnsZone.id : newBlobPrivateDnsZone.outputs.blobPrivateDnsZoneId
        }
      }
    ]
  }
}

output storageAccountName string = storageAccount.name
