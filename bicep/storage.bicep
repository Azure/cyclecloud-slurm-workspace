targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param saName string
param subnetId string
param privateDnsZoneId string

var privateDnsZoneExists = privateDnsZoneId != ''
var privateDnsZoneResourceGroup = split(privateDnsZoneId, '/')[4]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: saName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties:{
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      }      
  }
}

var storageBlobPrivateEndpointName = 'ccwstorage-blob-pe'

resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-04-01' =  {
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

module newBlobPrivateDnsZone 'storage-newDnsZone.bicep' = if (!privateDnsZoneExists) {
  name: 'ccwStorageNewDnsZone'
  params: {
    name: blobPrivateDnsZoneName
    storageAccountId: storageAccount.id
    subnetId: subnetId
    tags: tags
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (privateDnsZoneExists) {
  name: blobPrivateDnsZoneName
  scope: resourceGroup(privateDnsZoneResourceGroup)
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: blobPrivateDnsZoneName
        properties:{
          privateDnsZoneId: privateDnsZoneExists ? blobPrivateDnsZone.id : newBlobPrivateDnsZone.outputs.blobPrivateDnsZoneId
        }
      }
    ]
  }
}

output storageAccountName string = storageAccount.name
