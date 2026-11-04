targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param adminUser string
@secure()
param adminPassword string
@description('Provide the tier of the particular SKU. High Availability is available only for GeneralPurpose and MemoryOptimized sku.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param serverEdition string 
@description('The name of the sku, e.g. Standard_D32ds_v4.')
param skuName string 

// Create a MySQL Flexible Server
resource server 'Microsoft.DBforMySQL/flexibleServers@2024-12-30' = {
  location: location
  tags: tags
  name: 'ccw-mysqldb-${uniqueString(az.resourceGroup().id)}'
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
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

//output fqdn string = reference(server.id, server.apiVersion, 'full').properties.fullyQualifiedDomainName
output fqdn string = server.properties.fullyQualifiedDomainName
output dbId string = server.id
