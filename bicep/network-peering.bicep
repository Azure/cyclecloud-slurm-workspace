targetScope = 'resourceGroup'

@description('Peer name')
param name string

@description('VNet name to peer to')
param vnetName string

@description('allow gateway transit (default: true)')
param allowGateway bool = true

@description('VNET Id of the ccw VNET')
param vnetId string

resource peeredVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' existing = { 
  name: vnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: name
  parent: peeredVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: allowGateway
    remoteVirtualNetwork: {
      id: vnetId
    }
  }
}
