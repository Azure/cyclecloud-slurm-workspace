targetScope = 'resourceGroup'

param name string
param location string
param resourcePostfix string = uniqueString(resourceGroup().id,deployment().name)
param subnetId string
param serviceLevel string
param sizeGB int

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2022-05-01' = {
  name: '${name}-account-${resourcePostfix}'
  location: location
}

resource anfPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2022-05-01' = {
  name: '${name}-anf-pool'
  location: location
  parent: anfAccount
  properties: {
    serviceLevel: serviceLevel
    size: sizeGB * 1024 * 1024 * 1024 *1024
  }
}

resource anfHome 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2022-05-01' = {
  name: '${name}-anf-home'
  location: location
  parent: anfPool
  properties: {
    creationToken: 'home-${name}'
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
output anf_volume_name string = anfHome.name
output nfs_home_ip string = anfHome.properties.mountTargets[0].ipAddress
output nfs_home_path string = 'home-${resourcePostfix}'
output nfs_home_opts string = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'
