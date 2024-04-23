targetScope = 'resourceGroup'

param location string
param name string
param allowedSubnetIds array
param sizeGB int

resource nfsFilesStorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: '${name}${take(uniqueString(resourceGroup().id,deployment().name),18)}'
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'FileStorage'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: [
        for id in allowedSubnetIds: {
          id: id
          action: 'Allow'
          state: 'Succeeded'
        }
      ]
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: false
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource nfsFilesFileServices 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  parent: nfsFilesStorageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        multichannel: {
          enabled: false
        }
      }
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource nfsFilesHome 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  parent: nfsFilesFileServices
  name: 'nfshome'
  properties: {
    accessTier: 'Premium'
    shareQuota: sizeGB
    enabledProtocols: 'NFS'
    rootSquash: 'NoRootSquash'
  }
}

output nfs_home_ip string = '${nfsFilesStorageAccount.name}.file.${environment().suffixes.storage}'
output nfs_home_path string = '/${nfsFilesStorageAccount.name}/nfshome'
output nfs_home_opts string = 'vers=4,minorversion=1,sec=sys'
