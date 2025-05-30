
param location string = resourceGroup().location
param virtualNetworkName string = 'hub-vnet-${resourceGroup().name}'
param gatewaySubnetName string = 'GatewaySubnet'
param publicIpName string = '${resourceGroup().name}-vpn-gateway-ip'
param vpnGatewayName string = '${resourceGroup().name}-vpn-gateway'

param addressPrefix string = '10.0.1.0/24'

resource existingVnet 'Microsoft.Network/virtualNetworks@2021-02-01' existing = {
  name: virtualNetworkName
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  name: 'GatewaySubnet'
  parent: existingVnet
  properties: {
    addressPrefix: addressPrefix
  }
}


resource publicIp 'Microsoft.Network/publicIPAddresses@2020-11-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2020-11-01' = {
  name: vpnGatewayName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: gatewaySubnet.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    activeActive: false
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
  }
}

