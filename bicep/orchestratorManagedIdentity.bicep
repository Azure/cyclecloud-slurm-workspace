targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string = 'ccwOrchestratorManagedIdentity'
param location string
param applyRoleAssignments bool = true
param tags tags_t = {}

//create managed identity for CycleCloud VM
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

module ccwCycleCloudVirtualMachineRoleAssignments './orchestratorManagedIdentityRoleAssignments.bicep' = if (applyRoleAssignments) {
  name: 'ccwOrchestratorRoles-${uniqueString(az.resourceGroup().id, name, location)}'
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

output managedIdentityId string = managedIdentity.id
