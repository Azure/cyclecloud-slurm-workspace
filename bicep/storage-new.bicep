targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

var storageAccountName = 'ccwstorage${uniqueString(az.resourceGroup().id)}'
param location string
param tags tags_t = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties:{
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      }      
  }
}

output storageAccountName string = storageAccount.name
