targetScope = 'resourceGroup'
import * as types from './types.bicep'

param name string
param location string
param networkInterfacesTags types.tags_t
param subnetId string

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${name}-nic'
  location: location
  tags: networkInterfacesTags
  properties: {
    ipConfigurations: [
      {
        name: '${name}-ipconfig'
        properties: {
            subnet: {
              id: subnetId
            }
            privateIPAllocationMethod: 'Dynamic'
          }
      }
    ]
  }
}

output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
