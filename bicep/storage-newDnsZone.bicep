targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param tags tags_t

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: name
  location: 'global'
  tags: tags
}

output blobPrivateDnsZoneId string = blobPrivateDnsZone.id
output blobPrivateDnsZoneName string = blobPrivateDnsZone.name
