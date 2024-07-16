targetScope = 'resourceGroup'

param location string
param tags object
param saName string
param lockDownNetwork bool
// param allowableIps array
param subnetIds array

// var ips = [ for ip in allowableIps : { value: ip } ]
var subIds = [ for id in subnetIds : { id: id } ]

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: saName
  location: location
  tags: tags
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
        // ipRules: ips
          //map(allowableIps, ip => { value: ip })
        virtualNetworkRules: subIds
          //map(subnetIds, id => { id: id })
      }
    } : {}
  )
}

output storageAccountName string = storageAccount.name
