targetScope = 'resourceGroup'
import * as types from './types.bicep'

param location string
param kvName string
param subnetId string
param keyvaultOwnerId string 
param lockDownNetwork bool 
param kvPairs types.keyVaultPairs_t

output keyvaultName string = kvName

resource ccswKV 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    tenantId: subscription().tenantId
    softDeleteRetentionInDays: 90
    enableSoftDelete: true
    enablePurgeProtection: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: lockDownNetwork ? 'Deny' : 'Allow'
      //ipRules: map(allowableIps, ip => { value: ip })
      virtualNetworkRules: [
        {
          id: subnetId
        }
      ]
    }
    accessPolicies: [{
      objectId: keyvaultOwnerId
      permissions: {
        secrets: ['All']
      }
      tenantId: subscription().tenantId
    }]
    enableRbacAuthorization: true
  }
}

resource kvRA 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kvName, resourceGroup().id, subnetId)
  scope: ccswKV
  properties: {
    roleDefinitionId: resourceId('microsoft.authorization/roleDefinitions','b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: keyvaultOwnerId
    principalType: 'User'
  }
}

resource kvSecret 'Microsoft.KeyVault/vaults/secrets@2022-11-01' = [for kvPair in items(kvPairs): {
  name: kvPair.key
  parent: ccswKV
  properties: {
    value: kvPair.value
  }
}]
