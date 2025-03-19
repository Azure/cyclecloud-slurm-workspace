targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param saName string
param subnetId string
param privateDnsZoneExists bool 

var virtualNetworkResourceGroup = split(subnetId, '/')[4]
var virtualNetworkName = split(subnetId, '/')[8]

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
    vnetResourceGroup: virtualNetworkResourceGroup
    vnetName: virtualNetworkName
    tags: tags
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (privateDnsZoneExists) {
  name: blobPrivateDnsZoneName
  scope: resourceGroup(virtualNetworkResourceGroup)
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
