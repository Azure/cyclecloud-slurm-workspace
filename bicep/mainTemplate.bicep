targetScope = 'subscription'
import * as types from './types.bicep'

param location string
param adminUsername string
@secure()
param adminPassword string
param adminSshPublicKey string = '' 
param storedKey types.storedKey_t = {id: 'foo', location: 'foo', name:'foo'}
@minLength(1)
@maxLength(64)
param ccVMName string
param ccVMSize string
param resourceGroup string
param sharedFilesystem types.sharedFilesystem_t
param additionalFilesystem types.additionalFilesystem_t = { type: 'disabled' }
param network types.vnet_t
param slurmSettings types.slurmSettings_t = { version: '23.11.7-1', healthCheckEnabled: false }
param schedulerNode types.scheduler_t
param loginNodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.resource_tags_t 
@secure()
param databaseAdminPassword string = ''
param databaseConfig types.databaseConfig_t = { type: 'disabled' }
@minLength(3)
@description('The user-defined name of the cluster. Regex: ^[a-zA-Z0-9@_-]{3,}$')
param clusterName string = 'ccw'
param acceptMarketplaceTerms bool = false
param deployOOD bool = false
param infrastructureOnly bool = false
param insidersBuild bool = false

// build.sh will override this, but for development please set this yourself as a parameter
param branch string = 'main'
// This needs to be updated on each release. Our Cloud.Project records require a release tag
param projectVersion string = '2024.12.18'
//Internal developer use only: set true use custom CycleCloud release build 
param manualInstall bool = false

resource ccwResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroup
  location: location
  tags: tags[?'Resource group'] ?? {}
}

module makeCCWresources 'ccw.bicep' = {
  name: 'pid-d5d2708b-a4ef-42c0-a89b-b8bd6dd6d29b-partnercenter'
  scope: ccwResourceGroup
  params: {
    location: location
    infrastructureOnly: infrastructureOnly
    insidersBuild: insidersBuild
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
    ccVMName: ccVMName
    ccVMSize: ccVMSize
    resourceGroup: resourceGroup
    databaseAdminPassword: databaseAdminPassword
    databaseConfig: databaseConfig
    tags: tags
    clusterName: clusterName
    branch: branch
    projectVersion: projectVersion
    manualInstall: manualInstall
    acceptMarketplaceTerms: acceptMarketplaceTerms
    deployOOD : deployOOD
  }
}
