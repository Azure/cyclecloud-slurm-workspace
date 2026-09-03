targetScope = 'resourceGroup'
import {privateDnsZone_t,tags_t} from './types.bicep'

param location string
param tags tags_t
param resourceId string
param computeSubnetId string
param privateDnsZone privateDnsZone_t
@allowed(['blob','mysqlServer'])
param groupId string

var dict = {
  blob: {
    prefix: 'ccwStorage'
    privateDnsZoneName: 'privatelink.blob.${environment().suffixes.storage}'
  }
  mysqlServer: {
    prefix: 'ccwDatabase'
    privateDnsZoneName: 'privatelink.mysql.database.${environment().name == 'AzureUSGovernment' ? 'usgovcloudapi.net' : 'azure.com'}'
  }
}

var privateDnsZoneId = privateDnsZone.?id ?? 'a0a0a0a0/bbbb/cccc/dddd/eeee/ffff/aaaa/bbbb/c8c8c8c8'
var privateDnsZoneResourceGroup = split(privateDnsZoneId, '/')[4]
var createVnetLink = privateDnsZone.type == 'existing' ? privateDnsZone.vnetLink : privateDnsZone.type == 'new'
var vnetLinkScope = privateDnsZone.type == 'existing' ? split(privateDnsZoneId, '/')[4] : az.resourceGroup().name

var privateEndpointName = '${dict[groupId].prefix}-${groupId}-pe'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2025-05-01' = {
  name: privateEndpointName
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      { 
        name: privateEndpointName
        properties: {
          groupIds: [
            groupId
          ]
          privateLinkServiceId: resourceId
          privateLinkServiceConnectionState: {
            status: 'Approved'
            description: 'Auto-Approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
    customNetworkInterfaceName: '${privateEndpointName}-nic'
    subnet: {
      id: computeSubnetId
    }
  }
}

module newPrivateDnsZone 'privateDnsZone.bicep' = if (privateDnsZone.type == 'new') {
  name: '${dict[groupId].prefix}NewDnsZone'
  params: {
    name: dict[groupId].privateDnsZoneName
    tags: tags
  }
}

resource existingPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (privateDnsZone.type == 'existing') {
  name: split(privateDnsZoneId, '/')[8]
  scope: resourceGroup(privateDnsZoneResourceGroup)
}

module privateDnsZoneVnetLink 'vnetLink.bicep' = if (createVnetLink) {
  name: '${dict[groupId].prefix}${toUpper(substring(groupId, 0, 1))}${substring(groupId, 1)}PrivateDnsZoneVnetLink'
  scope: resourceGroup(vnetLinkScope)
  params: {
    resourceId: resourceId
    subnetId: computeSubnetId
    privateDnsZoneName: privateDnsZone.type == 'existing' ? existingPrivateDnsZone.name : newPrivateDnsZone!.outputs.privateDnsZoneName //force dependency
    tags: tags
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2025-05-01' = if (privateDnsZone.type != 'none') {
  parent: privateEndpoint
  name: 'default'
  properties:{
    privateDnsZoneConfigs: [
      {
        name: dict[groupId].privateDnsZoneName
        properties:{
          privateDnsZoneId: privateDnsZone.type == 'existing' ? existingPrivateDnsZone.id : newPrivateDnsZone!.outputs.privateDnsZoneId
        }
      }
    ]
  }
}

