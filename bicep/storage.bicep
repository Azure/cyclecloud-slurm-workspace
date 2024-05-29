targetScope = 'resourceGroup'

param location string
param saName string
param lockDownNetwork bool
param allowableIps array
param subnetIds array

var ips = [ for ip in allowableIps : { value: ip } ]
var subIds = [ for id in subnetIds : { id: id } ]

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: saName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: union(
    {
      accessTier: 'Hot'
      minimumTlsVersion: 'TLS1_2'
    },
    lockDownNetwork ? {
      networkAcls: {
        defaultAction: 'Deny'
        ipRules: ips
          //map(allowableIps, ip => { value: ip })
        virtualNetworkRules: subIds
          //map(subnetIds, id => { id: id })
      }
    } : {}
  )
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}

// TODO: Need to remove as we can't attach a container to AMLFS in this version of the AMLFS RP
// If so it has to be dependent on the AMLFS creation
resource lustreArchive 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'lustre'
  parent: blobServices
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
