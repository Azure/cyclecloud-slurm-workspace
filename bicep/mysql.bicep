targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param adminUser string
@secure()
param adminPassword string
param subnetId string
@description('Provide the tier of the particular SKU. High Availability is available only for GeneralPurpose and MemoryOptimized sku.')
@allowed([
  'Burstable'
  'Generalpurpose'
  'MemoryOptimized'
])
param serverEdition string = 'Burstable'
@description('The name of the sku, e.g. Standard_D32ds_v4.')
param skuName string = 'Standard_B2ms'

// Create a MySQL Flexible Server
resource server 'Microsoft.DBforMySQL/flexibleServers@2024-12-30' = {
  location: location
  tags: tags
  name: 'hub-mysql-${resourceGroup().name}'
  sku: {
    name: skuName
    tier: serverEdition
  }
  properties: {
    version: '8.0.21'
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
//    availabilityZone: ''
    highAvailability: {
      mode: 'Disabled'
//      standbyAvailabilityZone: standbyAvailabilityZone
    }
    storage: {
      storageSizeGB: 20
      iops: 360
      autoGrow: 'Enabled'
    }
    network: {
      delegatedSubnetResourceId: subnetId
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource require_secure_transport 'Microsoft.DBforMySQL/flexibleServers/configurations@2024-12-30' = {
  name: 'require_secure_transport'
  parent: server
  properties: {
    value: 'OFF'
    source: 'user-override'
  }
}

//output fqdn string = reference(server.id, server.apiVersion, 'full').properties.fullyQualifiedDomainName
output fqdn string = server.properties.fullyQualifiedDomainName
