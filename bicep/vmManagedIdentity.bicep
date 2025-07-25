targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param location string
param applyRoleAssignments bool = true
param tags tags_t = {}

//create managed identity for CycleCloud VM
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

module ccwCycleCloudVirtualMachineRoleAssignments './vmManagedIdentityRoleAssignments.bicep' = if (applyRoleAssignments) {
  name: 'ccwRoleForCycleCloudVirtualMachine-${location}'
  scope: subscription()
  params: {
    roles: [
      'Contributor'
      'Storage Account Contributor'
      'Storage Blob Data Contributor'
    ]
    principalId: managedIdentity.properties.principalId
  }
}
