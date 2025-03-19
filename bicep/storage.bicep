targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param saName string
param subnetId string

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

resource existingBlobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: blobPrivateDnsZoneName
  scope: resourceGroup(virtualNetworkResourceGroup)
}
var privateDnsZoneExists = existingBlobPrivateDnsZone.name != ''

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (!privateDnsZoneExists)  {
  name: blobPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: blobPrivateDnsZoneName
        properties:{
          privateDnsZoneId: privateDnsZoneExists ? existingBlobPrivateDnsZone.id : blobPrivateDnsZone.id
        }
      }
    ]
  }
}


resource blobPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (!privateDnsZoneExists)  {
  parent: blobPrivateDnsZone
  name: uniqueString(storageAccount.id)
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: resourceId(virtualNetworkResourceGroup,'Microsoft.Network/virtualNetworks', virtualNetworkName)
    }
  }
}

output storageAccountName string = storageAccount.name
