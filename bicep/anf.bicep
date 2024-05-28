targetScope = 'resourceGroup'

param name string
param location string
param tags object
param resourcePostfix string = uniqueString(resourceGroup().id)
param subnetId string
param serviceLevel string
param sizeGB int

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2022-05-01' = {
  name: 'hpcanfaccount-${take(resourcePostfix,10)}'
  location: location
}

resource anfPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2022-05-01' = {
  name: '${name}-anf-pool'
  location: location
  tags: tags
  parent: anfAccount
  properties: {
    serviceLevel: serviceLevel
    size: sizeGB * 1024 * 1024 * 1024 *1024
  }
}

resource anfVolume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2022-05-01' = {
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
    usageThreshold: sizeGB * 1024 * 1024 * 1024 *1024

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

output anf_account_name string = anfAccount.name
output anf_pool_name string = anfPool.name
output anf_volume_name string = anfVolume.name
output anf_ip string = anfVolume.properties.mountTargets[0].ipAddress
output anf_export_path string = '/${name}-path'
output anf_opts string = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'

// Require fs_module outputs
output ip_address string = anfVolume.properties.mountTargets[0].ipAddress
output export_path string = '/${name}-path'
output mount_options string = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'
