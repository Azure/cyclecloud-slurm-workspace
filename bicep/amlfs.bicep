targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param location string
param tags tags_t
param name string
param subnetId string
@allowed([
  'AMLFS-Durable-Premium-40'
  'AMLFS-Durable-Premium-125'
  'AMLFS-Durable-Premium-250'
  'AMLFS-Durable-Premium-500'
])
param sku string
@description('''
The step sizes are dependent on the SKU.
- AMLFS-Durable-Premium-40: 48TB
- AMLFS-Durable-Premium-125: 16TB
- AMLFS-Durable-Premium-250: 8TB
- AMLFS-Durable-Premium-500: 4TB
''')
param capacity int
param infrastructureOnly bool = false

resource fileSystem 'Microsoft.StorageCache/amlFileSystems@2023-05-01' = if (!infrastructureOnly){
  name: '${name}-${uniqueString(resourceGroup().id,deployment().name)}'
  location: location
  tags: tags
  sku: {
    name: sku
  }
  zones: [ '1' ]
  properties: {
    storageCapacityTiB: capacity
    filesystemSubnet: subnetId
    maintenanceWindow: {
      dayOfWeek: 'Saturday'
      timeOfDayUTC: '23:00'
    }
  }
}

// All fs modules must output ip_address, export_path and mount_options
output ip_address string = infrastructureOnly ? '' : fileSystem.properties.clientInfo.mgsAddress
// TODO we are fighting the chef cookbooks here by adding tcp:/lustrefs, as it simply prepends all paths
// with tcp:/lustrefs
output export_path string = '' //what should our placeholder be for new amlfs??
output mount_options string = ''
