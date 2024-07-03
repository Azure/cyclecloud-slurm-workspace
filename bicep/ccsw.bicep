targetScope = 'resourceGroup'
//import {shared_filesystem_t, additional_filesystem_t, vnet_t, tags_t, slurmSettings_t, login_t, htc_t, hpc_t, htc_output_t} from './types.bicep'
import * as types from './types.bicep'

param location string = resourceGroup().location
param infrastructureOnly bool

param branch string
param project_version string

param adminUsername string
@secure()
param adminPassword string
//param adminKeyphrase string
param adminSshPublicKey string
param storedKey object
param ccVMSize string
param resource_group string //
param shared_filesystem types.shared_filesystem_t
param additional_filesystem types.additional_filesystem_t = { type: 'disabled' }
param network types.vnet_t = {
  type: 'new'
  address_space: '10.0.0.0/24'
}
param slurmSettings types.slurmSettings_t = { version: '23.11.7-1', healthCheckEnabled: false}
param scheduler_node types.scheduler_t
param login_nodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.tags_t
@secure()
param databaseAdminPassword string

var anfDefaultMountOptions = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'

func getTags(resource_type string, tags object) object => tags[?resource_type] ?? {}

var useEnteredKey = adminSshPublicKey != ''
module ccswPublicKey './publicKey.bicep' = if (!useEnteredKey && !infrastructureOnly) {
  name: 'ccswPublicKey'
  params: {
    storedKey: storedKey
  }
}
var publicKey = infrastructureOnly ? '' : (useEnteredKey ? adminSshPublicKey : ccswPublicKey.outputs.publicKey)

var create_nat_gateway = contains(network, 'create_nat_gateway')
module natgateway './natgateway.bicep' = if (create_nat_gateway) {
  name: 'natgateway'
  params: {
    location: location
    tags: getTags('Microsoft.Network/natGateways', tags)
    name: 'ccsw-nat-gateway'
  }
}
var natGateawayId = create_nat_gateway ? natgateway.outputs.NATGatewayId : ''

var create_new_vnet = network.type == 'new'
module ccswNetwork './network-new.bicep' = if (create_new_vnet) {
  name: 'ccswNetwork'
  params: {
    location: location
    tags: getTags('Microsoft.Network/virtualNetworks', tags)
    nsgTags: getTags('Microsoft.Network/networkSecurityGroups', tags)
    network: network
    natGatewayId: natGateawayId
    shared_filesystem: shared_filesystem
    additional_filesystem: additional_filesystem
  }
}

var vnet = create_new_vnet ? ccswNetwork.outputs.vnet_ccsw : {}
var subnets = create_new_vnet
  ? ccswNetwork.outputs.subnets_ccsw
  : {
      cyclecloud: { id: join([network.?id, 'subnets', network.?cyclecloudSubnet], '/') }
      compute: { id: join([network.?id, 'subnets', network.?computeSubnet], '/') }
      home: { id: join([network.?id, 'subnets', network.?sharedFilerSubnet ?? 'null'], '/') }
      additional: { id: join([network.?id, 'subnets', network.?additionalFilerSubnet ?? 'null'], '/') }
    }

output vnet object = vnet

var deploy_bastion = network.?bastion ?? false
module ccswBastion './bastion.bicep' = if (deploy_bastion) {
  name: 'ccswBastion'
  scope: create_new_vnet ? resourceGroup() : resourceGroup(split(network.?existing_vnet_id, '/')[4])
  params: {
    location: location
    tags: getTags('Microsoft.Network/bastionHosts', tags)
    subnetId: subnets.bastion.id
  }
}

param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:8.6.220240605'

var vmName = 'ccsw-cyclecloud'
module ccswVM './vm.bicep' =  if (!infrastructureOnly) {
    name: 'ccswVM-cyclecloud'
    params: {
      location: location
      tags: getTags('Microsoft.Compute/virtualMachines', tags)
      networkInterfacesTags: getTags('Microsoft.Network/networkInterfaces', tags)
      name: vmName
      deployScript: loadTextContent('./install.sh')
      osDiskSku: 'StandardSSD_LRS'
      image: {
        plan: 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2'
        ref: contains(cyclecloudBaseImage, '/')
          ? {
              id: cyclecloudBaseImage
            }
          : {
              publisher: split(cyclecloudBaseImage, ':')[0]
              offer: split(cyclecloudBaseImage, ':')[1]
              sku: split(cyclecloudBaseImage, ':')[2]
              version: split(cyclecloudBaseImage, ':')[3]
            }
      }
      subnetId: subnets.cyclecloud.id 
      adminUser: adminUsername
      adminSshPublicKey: publicKey
      vmSize: ccVMSize
      dataDisks: [
        {
          name: 'ccsw-cyclecloud-vm-datadisk0'
          disksku: 'Premium_LRS'
          size: split(cyclecloudBaseImage, ':')[0] == 'azurecyclecloud' ? 0 : 128
          caching: 'ReadWrite'
          createOption: split(cyclecloudBaseImage, ':')[0] == 'azurecyclecloud' ? 'FromImage' : 'Empty'
        }
      ]

    }
    dependsOn: [
      ccswNetwork
    ]
  }

module ccswRolesAssignments './roleAssignments.bicep' =  if (!infrastructureOnly) {
    name: 'ccswRoleFor-${vmName}-${location}'
    scope: subscription()
    params: {
      name: vmName
      rgID: resourceGroup().id
      roles: [
        'Contributor'
        'Storage Account Contributor'
        'Storage Blob Data Contributor'
      ]
      principalId: ccswVM.outputs.principalId
    }
    dependsOn: [
      ccswVM
    ]
  }

module ccswStorage './storage.bicep' = {
  name: 'ccswStorage'
  params: {
    location: location
    tags: getTags('Microsoft.Storage/storageAccounts', tags)
    saName: 'ccswstorage${uniqueString(resourceGroup().id)}'
    lockDownNetwork: true // Restrict access to the storage account from compute and cyclecloud subnets
    subnetIds: concat([subnets.compute.id], [subnets.cyclecloud.id])
  }
}

var create_database = contains(slurmSettings, 'databaseAdminPassword')
var db_name = 'ccsw-mysqldb-${uniqueString(resourceGroup().id)}'

module mySQLccsw './mysql.bicep' = if (create_database) {
  name: 'MySQLDB-ccsw'
  params: {
    location: location
    tags: getTags('Microsoft.DBforMySQL/flexibleServers', tags)
    Name: db_name
    adminUser: adminUsername
    adminPassword: databaseAdminPassword
    subnetId: subnets.database.id 
  }
}

module ccswAMLFS 'amlfs.bicep' = if (additional_filesystem.type == 'aml-new') {
  name: 'ccswAMLFS-additional'
  params: {
    location: location
    tags: getTags('Microsoft.StorageCache/amlFileSystems', tags)
    name: 'ccsw-lustre'
    subnetId: subnets.additional.id
    sku: additional_filesystem.?lustre_tier
    capacity: additional_filesystem.?lustre_capacity_in_tib
    infrastructureOnly: infrastructureOnly
  }
  dependsOn: [
    ccswNetwork
  ]
}

module ccswANF 'anf.bicep' = [
  for filer in items({home: shared_filesystem, additional: additional_filesystem}): if (filer.value.type == 'anf-new') {
    name: 'ccswANF-${filer.key}'
    params: {
      location: location
      tags: getTags('Microsoft.NetApp/netAppAccounts', tags)
      name: filer.key
      subnetId: subnets[filer.key].id
      serviceLevel: filer.value.anf_service_tier
      sizeGB: int(filer.value.anf_capacity_in_bytes)
      defaultMountOptions: anfDefaultMountOptions
      infrastructureOnly: infrastructureOnly
    }
    dependsOn: [
      ccswNetwork
    ]
  }
]

//TODO: review mount options esp. re: anf, aml
output filer_info_final object = {
  home: {
    type: shared_filesystem.type
    nfs_capacity_in_gb: shared_filesystem.?nfs_capacity_in_gb ?? ''
    ip_address: shared_filesystem.type == 'anf-new' ? ccswANF[1].outputs.ip_address : shared_filesystem.?ip_address ?? ''
    export_path: shared_filesystem.type == 'anf-new' ? ccswANF[1].outputs.export_path : shared_filesystem.?export_path ?? ''
    mount_options: shared_filesystem.type == 'anf-new' ? ccswANF[1].outputs.mount_options : shared_filesystem.?mount_options ?? ''
    mount_path: '/shared'
  }
  additional: {
    type: additional_filesystem.type
    ip_address: additional_filesystem.type == 'anf-new'
      ? ccswANF[0].outputs.ip_address
      : additional_filesystem.type == 'aml-new' ? ccswAMLFS.outputs.ip_address : additional_filesystem.?ip_address ?? ''
    export_path: additional_filesystem.?export_path ?? ''
    mount_options: additional_filesystem.type == 'anf-new'
      ? ccswANF[0].outputs.mount_options
      : additional_filesystem.?mount_options ?? ''
    mount_path: additional_filesystem.?mount_path ?? ''
  }
}

output cyclecloudPrincipalId string = infrastructureOnly ? '' : ccswVM.outputs.principalId

output slurmSettings types.slurmSettings_t = slurmSettings

output schedulerNode types.scheduler_t = scheduler_node

output loginNodes types.login_t = login_nodes

output partitions types.partitions_t = {
  htc: {
    vmSize: htc.vmSize
    maxNodes: htc.maxNodes
    image: htc.image
    useSpot: htc.?useSpot ?? false
  }
  hpc: hpc
  gpu: gpu
}

var envNameToCloudMap = {
  AzureCloud: 'AZUREPUBLICCLOUD'
  AzureUSGovernment: 'AZUREUSGOVERNMENT'
  AzureGermanCloud: 'AZUREGERMANCLOUD'
  AzureChinaCloud: 'AZURECHINACLOUD'
}
var pword = split('foo-${adminPassword}-foo', '-')[1] //workaround linter & arm-ttk

//FIX: remove old comments and clean up
output ccswGlobalConfig object = union(
  {
    resourceGroup: resource_group
    location: location
    global_cc_storage: ccswStorage.outputs.storageAccountName
    computeSubnetID: subnets.compute.id
    publicKey: publicKey
    adminUsername: adminUsername
    adminPassword: pword
    homedir_mountpoint: '/nfshome' //FIX cribbed from AzHop, unsure if correct
    subscription_id: subscription().subscriptionId
    tenant_id: subscription().tenantId
    lustre_hsm_storage_account: ccswStorage.outputs.storageAccountName
    lustre_hsm_storage_container: 'lustre'
    database_fqdn: create_database ? mySQLccsw.outputs.fqdn : ''
    database_user: adminUsername
    azure_environment: envNameToCloudMap[environment().name]
    blob_storage_suffix: 'blob.${environment().suffixes.storage}' // blob.core.windows.net
  },
  {}
)

output branch string = branch
output project_version string = project_version
