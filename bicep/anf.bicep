targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param tags tags_t
param resourcePostfix string = uniqueString(resourceGroup().id)
param subnetId string
param serviceLevel string
param sizeTiB int
param defaultMountOptions string
param infrastructureOnly bool = false
var capacity = sizeTiB * 1024 * 1024 * 1024 * 1024

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2023-11-01' existing = if(!infrastructureOnly){
  name: 'hpcanfaccount-${take(resourcePostfix,10)}'
}

resource anfPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2024-01-01' = if(!infrastructureOnly){
  name: '${name}-anf-pool'
  location: location
  tags: tags
  parent: anfAccount
  properties: {
    serviceLevel: serviceLevel
    size: capacity
  }
}

resource anfVolume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-11-01' = if(!infrastructureOnly){
  name: '${name}-anf-volume'
  location: location
  tags: tags
  parent: anfPool
  properties: {
    unixPermissions: '0755'
    creationToken: '${name}-path'
    serviceLevel: serviceLevel
    networkFeatures: 'Standard'
    subnetId: subnetId
    protocolTypes: ['NFSv3']
    securityStyle: 'unix'
    usageThreshold: capacity

    exportPolicy: {
      rules: [
        {
            ruleIndex: 1
            unixReadOnly: false
            unixReadWrite: true
            cifs: false
            nfsv3: true
            nfsv41: false
            allowedClients: '0.0.0.0/0'
            kerberos5ReadOnly: false
            kerberos5ReadWrite: false
            kerberos5iReadOnly: false
            kerberos5iReadWrite: false
            kerberos5pReadOnly: false
            kerberos5pReadWrite: false
            hasRootAccess: true
            chownMode: 'Restricted'
        }
      ]
    }
  }
}


// Require fs_module outputs
output ipAddress string = infrastructureOnly ? '' :anfVolume.properties.mountTargets[0].ipAddress
output exportPath string = '/${name}-path'
output mountOptions string = defaultMountOptions
