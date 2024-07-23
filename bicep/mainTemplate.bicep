targetScope = 'subscription'
import * as types from './types.bicep'

param location string
param adminUsername string
@secure()
param adminPassword string
//param adminKeyphrase string
param adminSshPublicKey string = '' 
param storedKey object = {} //TODO: make type
param ccVMSize string
param resource_group string
param shared_filesystem types.shared_filesystem_t
param additional_filesystem types.additional_filesystem_t 
param network types.vnet_t
param slurmSettings types.slurmSettings_t
param scheduler_node types.scheduler_t
param login_nodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.tags_t 
@secure()
param databaseAdminPassword string = ''

param infrastructureOnly bool = false

// build.sh will override this, but for development please set this yourself as a parameter
param branch string = 'main'
// This needs to be updated on each release. Our Cloud.Project records require a release tag
param project_version string = '2024.06.06'

resource ccswResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resource_group
  location: location
  tags: tags[?'Microsoft.Resources/resourceGroups'] ?? {}
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
    shared_filesystem: shared_filesystem
    additional_filesystem: additional_filesystem
    network: network
    slurmSettings: slurmSettings
    scheduler_node: scheduler_node
    login_nodes: login_nodes
    htc: htc
    hpc: hpc
    gpu: gpu
    storedKey: storedKey
    ccVMSize: ccVMSize
    resource_group: resource_group
    tags: tags
    databaseAdminPassword: databaseAdminPassword
    branch: branch
    project_version: project_version
  }
}
