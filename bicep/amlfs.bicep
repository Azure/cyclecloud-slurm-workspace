targetScope = 'resourceGroup'

param location string
param tags object
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

resource fileSystem 'Microsoft.StorageCache/amlFileSystems@2023-05-01' = {
  name: '${name}-${uniqueString(resourceGroup().id,deployment().name)}'
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    storageCapacityTiB: capacity
    filesystemSubnet: subnetId
    maintenanceWindow: {
      dayOfWeek: 'Saturday'
      timeOfDayUTC: '23:00'
    }
  }
}

//https://learn.microsoft.com/en-us/rest/api/storagecache/aml-filesystems/create-or-update?view=rest-storagecache-2023-05-01&tabs=HTTP
output lustre_mgs string = fileSystem.properties.clientInfo.mgsAddress //ip address
//output lustre_path string = fileSystem.properties.hsm.archiveStatus[0].filesystemPath
//output lustre_path string = fileSystem.properties.hsm.settings.importPrefix
output lustre_mountcommand string = fileSystem.properties.clientInfo.mountCommand

// All fs modules must output ip_address, export_path and mount_options
output ip_address string = fileSystem.properties.clientInfo.mgsAddress
// TODO we are fighting the chef cookbooks here by adding tcp:/lustrefs, as it simply prepends all paths
// with tcp:/lustrefs
output export_path string = ''
output mount_options string = ''
