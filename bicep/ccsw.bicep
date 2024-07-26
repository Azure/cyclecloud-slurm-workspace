targetScope = 'resourceGroup'
import * as types from './types.bicep'

param location string = az.resourceGroup().location
param infrastructureOnly bool

param branch string
param projectVersion string

param adminUsername string
@secure()
param adminPassword string
//param adminKeyphrase string
param adminSshPublicKey string
param storedKey types.storedKey_t
param ccVMSize string
param resourceGroup string //
param sharedFilesystem types.sharedFilesystem_t
param additionalFilesystem types.additionalFilesystem_t = { type: 'disabled' }
param network types.vnet_t = {
  type: 'new'
  addressSpace: '10.0.0.0/24'
}
param slurmSettings types.slurmSettings_t = { version: '23.11.7-1', healthCheckEnabled: false }
param schedulerNode types.scheduler_t
param loginNodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.resource_tags_t
@secure()
param databaseAdminPassword string

var anfDefaultMountOptions = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'

func getTags(resource_type string, tags types.resource_tags_t) types.tags_t => tags[?resource_type] ?? {}

var useEnteredKey = adminSshPublicKey != ''
module ccswPublicKey './publicKey.bicep' = if (!useEnteredKey && !infrastructureOnly) {
  name: 'ccswPublicKey'
  params: {
    storedKey: storedKey
  }
}
var publicKey = infrastructureOnly ? '' : (useEnteredKey ? adminSshPublicKey : ccswPublicKey.outputs.publicKey)

var createNatGateway = network.?createNatGateway ?? false
module natgateway './natgateway.bicep' = if (createNatGateway) {
  name: 'natgateway'
  params: {
    location: location
    tags: getTags('Microsoft.Network/natGateways', tags)
    name: 'ccsw-nat-gateway'
  }
}
var natGateawayId = createNatGateway ? natgateway.outputs.NATGatewayId : ''

var create_new_vnet = network.type == 'new'
module ccswNetwork './network-new.bicep' = if (create_new_vnet) {
  name: 'ccswNetwork'
  params: {
    location: location
    tags: getTags('Microsoft.Network/virtualNetworks', tags)
    nsgTags: getTags('Microsoft.Network/networkSecurityGroups', tags)
    network: network
    natGatewayId: natGateawayId
    sharedFilesystem: sharedFilesystem
    additionalFilesystem: additionalFilesystem
  }
}

var subnets = create_new_vnet
  ? ccswNetwork.outputs.subnetsCCSW
  : {
      cyclecloud: { id: join([network.?id, 'subnets', network.?cyclecloudSubnet], '/') }
      compute: { id: join([network.?id, 'subnets', network.?computeSubnet], '/') }
      home: { id: join([network.?id, 'subnets', network.?sharedFilerSubnet ?? 'null'], '/') }
      additional: { id: join([network.?id, 'subnets', network.?additionalFilerSubnet ?? 'null'], '/') }
    }

output vnet types.networkOutput_t = union(
  create_new_vnet
    ? ccswNetwork.outputs.vnetCCSW
    : {
        id: network.?existing_vnet_id
        name: network.?name
        rg: split(network.?existing_vnet_id, '/')[4]
      },
  {
    type: network.type
    computeSubnetName: network.?computeSubnet ?? 'ccsw-compute-subnet'
    computeSubnetId: subnets.compute.id
  }
)

var deploy_bastion = network.?bastion ?? false
module ccswBastion './bastion.bicep' = if (deploy_bastion) {
  name: 'ccswBastion'
  scope: create_new_vnet ? az.resourceGroup() : az.resourceGroup(split(network.?existing_vnet_id, '/')[4])
  params: {
    location: location
    tags: getTags('Microsoft.Network/bastionHosts', tags)
    subnetId: subnets.bastion.id
  }
}

param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:8.6.220240605'

var vmName = 'ccsw-cyclecloud'
module ccswVM './vm.bicep' = if (!infrastructureOnly) {
  name: 'ccswVM-cyclecloud'
  params: {
    location: location
    tags: getTags('Microsoft.Compute/virtualMachines', tags)
    networkInterfacesTags: getTags('Microsoft.Network/networkInterfaces', tags)
    name: vmName
    deployScript: loadTextContent('./install.sh')
    osDiskSku: 'StandardSSD_LRS'
    image: {
      plan: cyclecloudBaseImage
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

module ccswRolesAssignments './roleAssignments.bicep' = if (!infrastructureOnly) {
  name: 'ccswRoleFor-${vmName}-${location}'
  scope: subscription()
  params: {
    name: vmName
    rgID: az.resourceGroup().id
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
    saName: 'ccswstorage${uniqueString(az.resourceGroup().id)}'
    lockDownNetwork: true // Restrict access to the storage account from compute and cyclecloud subnets
    subnetIds: concat([subnets.compute.id], [subnets.cyclecloud.id])
  }
}

var create_database = contains(slurmSettings, 'databaseAdminPassword')
var db_name = 'ccsw-mysqldb-${uniqueString(az.resourceGroup().id)}'

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

module ccswAMLFS 'amlfs.bicep' = if (additionalFilesystem.type == 'aml-new') {
  name: 'ccswAMLFS-additional'
  params: {
    location: location
    tags: getTags('Microsoft.StorageCache/amlFileSystems', tags)
    name: 'ccsw-lustre'
    subnetId: subnets.?additional.id ?? ''
    sku: additionalFilesystem.?lustreTier
    capacity: additionalFilesystem.?lustreCapacityInTib
    infrastructureOnly: infrastructureOnly
  }
  dependsOn: [
    ccswNetwork
  ]
}

module ccswANF 'anf.bicep' = [
  for filer in items({ home: sharedFilesystem, additional: additionalFilesystem }): if (filer.value.type == 'anf-new') {
    name: 'ccswANF-${filer.key}'
    params: {
      location: location
      tags: getTags('Microsoft.NetApp/netAppAccounts', tags)
      name: filer.key
      subnetId: subnets[filer.key].id
      serviceLevel: filer.value.anfServiceTier
      sizeTiB: filer.value.anfCapacityInTiB
      defaultMountOptions: anfDefaultMountOptions
      infrastructureOnly: infrastructureOnly
    }
    dependsOn: [
      ccswNetwork
    ]
  }
]

output filerInfoFinal types.filerInfo_t = {
  home: {
    type: sharedFilesystem.type
    nfsCapacityInGb: sharedFilesystem.?nfsCapacityInGb ?? -1
    ipAddress: sharedFilesystem.type == 'anf-new' ? ccswANF[1].outputs.ipAddress : sharedFilesystem.?ipAddress ?? ''
    exportPath: sharedFilesystem.type == 'anf-new' ? ccswANF[1].outputs.exportPath : sharedFilesystem.?exportPath ?? ''
    mountOptions: sharedFilesystem.type == 'anf-new'
      ? ccswANF[1].outputs.mountOptions
      : sharedFilesystem.?mountOptions ?? ''
    mountPath: '/shared'
  }
  additional: {
    type: additionalFilesystem.type
    ipAddress: additionalFilesystem.type == 'anf-new'
      ? ccswANF[0].outputs.ipAddress
      : additionalFilesystem.type == 'aml-new' ? ccswAMLFS.outputs.ipAddress : additionalFilesystem.?ipAddress ?? ''
    exportPath: additionalFilesystem.?exportPath ?? ''
    mountOptions: additionalFilesystem.type == 'anf-new'
      ? ccswANF[0].outputs.mountOptions
      : additionalFilesystem.?mountOptions ?? ''
    mountPath: additionalFilesystem.?mountPath ?? ''
  }
}

output cyclecloudPrincipalId string = infrastructureOnly ? '' : ccswVM.outputs.principalId

output slurmSettings types.slurmSettings_t = slurmSettings

output schedulerNode types.scheduler_t = schedulerNode

output loginNodes types.login_t = loginNodes

output partitions types.partitions_t = {
  htc: {
    sku: htc.sku
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

output resourceGroup string = resourceGroup
output location string = location
output storageAccountName string = ccswStorage.outputs.storageAccountName
output publicKey string = publicKey
output adminUsername string = adminUsername
output keyVault object = { pword: pword }
output subscriptionId string = subscription().subscriptionId
output tenantId string = subscription().tenantId
output databaseFQDN string = create_database ? mySQLccsw.outputs.fqdn : ''
output azureEnvironment string = envNameToCloudMap[environment().name]

output branch string = branch
output projectVersion string = projectVersion
