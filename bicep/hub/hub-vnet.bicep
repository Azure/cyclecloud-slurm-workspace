targetScope = 'resourceGroup'
import { tags_t } from '../types.bicep'
import {subnet_config} from '../network-new.bicep'


param location string 
param address string
param tags tags_t = {}

var subnet_cidr = subnet_config(address)

var vnet  = {
  name: 'hub-vnet-${resourceGroup().name}'
  cidr: address
  subnets: {
      netapp: {
        name: 'netapp'
        cidr: subnet_cidr.netapp
        nat_gateway : false
        service_endpoints: []
        delegations: [
          'Microsoft.Netapp/volumes'
        ]
      }
      database: {
        name: 'database'
        cidr: subnet_cidr.database
        nat_gateway : false
        service_endpoints: []
        delegations: [
          'Microsoft.DBforMySQL/flexibleServers'
        ]
      }
    }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnet.name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnet.cidr]
    }
    subnets: [
      for subnet in items(vnet.subnets): {
        name: subnet.value.name
        properties: {
          addressPrefixes: [subnet.value.cidr]
          // natGateway: (natGatewayId != '' && subnet.value.nat_gateway) ? {
          //   id: natGatewayId
          // } : null
          // networkSecurityGroup: {
          //   id: ccwCommonNsg.id
          // }
          delegations: map(subnet.value.delegations, delegation => {
            name: subnet.value.name
            properties: {
              serviceName: delegation
            }
          })
          serviceEndpoints: map(subnet.value.service_endpoints, endpoint => {
            service: endpoint
          })
        }
      }
    ]
  }
}
