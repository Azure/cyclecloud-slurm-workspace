targetScope = 'subscription'
import * as types from './types.bicep'

param location string
param adminUsername string
@secure()
param adminPassword string
//param adminKeyphrase string
param adminSshPublicKey string = '' 
param storedKey types.storedKey_t = {id: 'foo', location: 'foo', name:'foo'}
param ccVMSize string
param resourceGroup string
param sharedFilesystem types.sharedFilesystem_t
param additionalFilesystem types.additionalFilesystem_t 
param network types.vnet_t
param slurmSettings types.slurmSettings_t
param schedulerNode types.scheduler_t
param loginNodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.resource_tags_t 
@secure()
param databaseAdminPassword string = ''

param infrastructureOnly bool = false

// build.sh will override this, but for development please set this yourself as a parameter
param branch string = 'main'
// This needs to be updated on each release. Our Cloud.Project records require a release tag
param projectVersion string = '2024.06.06'

resource ccswResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroup
  location: location
  tags: tags[?'Resource group'] ?? {}
}

module makeCCSWresources 'ccsw.bicep' = {
  name: 'pid-8d5b25bd-0ba7-49b9-90b3-3472bc08443e-partnercenter'
  scope: ccswResourceGroup
  params: {
    location: location
    infrastructureOnly: infrastructureOnly
    adminUsername: adminUsername
    adminPassword: adminPassword
    adminSshPublicKey: adminSshPublicKey
    sharedFilesystem: sharedFilesystem
    additionalFilesystem: additionalFilesystem
    network: network
    slurmSettings: slurmSettings
    schedulerNode: schedulerNode
    loginNodes: loginNodes
    htc: htc
    hpc: hpc
    gpu: gpu
    storedKey: storedKey
    ccVMSize: ccVMSize
    resourceGroup: resourceGroup
    tags: tags
    databaseAdminPassword: databaseAdminPassword
    branch: branch
    projectVersion: projectVersion
  }
}
