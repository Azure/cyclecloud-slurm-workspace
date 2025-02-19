targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param saName string
param lockDownNetwork bool
// param allowableIps array
param subnets object

// var ips = [ for ip in allowableIps : { value: ip } ]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: saName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: union(
    {
      accessTier: 'Hot'
      minimumTlsVersion: 'TLS1_2'
      allowSharedKeyAccess: false
      publicNetworkAccess: 'Disabled'
    },
    lockDownNetwork ? {
      networkAcls: {
        defaultAction: 'Deny'
        // ipRules: ips
          //map(allowableIps, ip => { value: ip })
      }
    } : {}
  )
}

var storagePrivateEndpointBlobPrefix = 'ccwstorage-blob-pe'

resource storagePrivateEndpointBlob 'Microsoft.Network/privateEndpoints@2023-04-01' = [ for subnet in items(subnets): {
  name: '${storagePrivateEndpointBlobPrefix}-${subnet.key}'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      { 
        name: '${storagePrivateEndpointBlobPrefix}-${subnet.key}'
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
    customNetworkInterfaceName: '${storagePrivateEndpointBlobPrefix}-${subnet.key}-nic'
    subnet: {
      id: subnet.value
    }
  }
}] 

var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: blobPrivateDnsZoneName
  location: 'global'
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-04-01' = [ for subnet in items(subnets):{
  name: '${storagePrivateEndpointBlobPrefix}-${subnet.key}/dnsGroup'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: blobPrivateDnsZoneName
        properties:{
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    storagePrivateEndpointBlob[subnet.key == 'compute' ? 0 : 1]
  ]
}]

var virtualNetworkId = resourceId('Microsoft.Network/virtualNetworks', split(subnets.compute, '/')[8])

resource blobPrivateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobPrivateDnsZone
  name: uniqueString(storageAccount.id)
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

output storageAccountName string = storageAccount.name
