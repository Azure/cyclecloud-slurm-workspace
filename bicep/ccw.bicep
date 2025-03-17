targetScope = 'resourceGroup'
import * as types from './types.bicep'

param location string 
param infrastructureOnly bool
param insidersBuild bool

param branch string
param projectVersion string
param pyxisProjectVersion string

param adminUsername string
@secure()
param adminPassword string
param adminSshPublicKey string
param storedKey types.storedKey_t
param ccVMName string
param ccVMSize string
param resourceGroup string
param sharedFilesystem types.sharedFilesystem_t
param additionalFilesystem types.additionalFilesystem_t 
param network types.vnet_t 
param clusterInitSpecs types.cluster_init_param_t
param slurmSettings types.slurmSettings_t 
param schedulerNode types.scheduler_t
param loginNodes types.login_t
param htc types.htc_t
param hpc types.hpc_t
param gpu types.hpc_t
param tags types.resource_tags_t
@secure()
param databaseAdminPassword string
param databaseConfig types.databaseConfig_t
param clusterName string
param manualInstall bool
param acceptMarketplaceTerms bool
param ood types.oodConfig_t

var anfDefaultMountOptions = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev,nconnect=8'

func getTags(resource_type string, tags types.resource_tags_t) types.tags_t => tags[?resource_type] ?? {}

var useEnteredKey = adminSshPublicKey != ''
module ccwPublicKey './publicKey.bicep' = if (!useEnteredKey && !infrastructureOnly) {
  name: 'ccwPublicKey'
  params: {
    storedKey: storedKey
  }
}
var publicKey = infrastructureOnly ? '' : (useEnteredKey ? adminSshPublicKey : ccwPublicKey.outputs.publicKey)

var createNatGateway = network.?createNatGateway ?? false
module natgateway './natgateway.bicep' = if (createNatGateway) {
  name: 'natgateway'
  params: {
    location: location
    tags: getTags('Microsoft.Network/natGateways', tags)
    name: 'ccw-nat-gateway'
  }
}
var natGateawayId = createNatGateway ? natgateway.outputs.NATGatewayId : ''

var create_new_vnet = network.type == 'new'
module ccwNetwork './network-new.bicep' = if (create_new_vnet) {
  name: 'ccwNetwork'
  params: {
    location: location
    tags: getTags('Microsoft.Network/virtualNetworks', tags)
    nsgTags: getTags('Microsoft.Network/networkSecurityGroups', tags)
    network: network
    natGatewayId: natGateawayId
    sharedFilesystem: sharedFilesystem
    additionalFilesystem: additionalFilesystem
    databaseConfig: databaseConfig
  }
}

var subnets = create_new_vnet
  ? ccwNetwork.outputs.subnetsCCW
  : {
      cyclecloud: { id: join([network.?id, 'subnets', network.?cyclecloudSubnet], '/') }
      compute: { id: join([network.?id, 'subnets', network.?computeSubnet], '/') }
      home: { id: join([network.?id, 'subnets', network.?sharedFilerSubnet ?? 'null'], '/') }
      additional: { id: join([network.?id, 'subnets', network.?additionalFilerSubnet ?? 'null'], '/') }
    }

output vnet types.networkOutput_t = union(
  create_new_vnet
    ? ccwNetwork.outputs.vnetCCW
    : {
        id: network.?id ?? ''
        name: network.?name
        rg: split(network.?id ?? '////', '/')[4]
      },
  {
    type: network.type
    computeSubnetName: network.?computeSubnet ?? 'ccw-compute-subnet'
    computeSubnetId: subnets.compute.id
  }
)

var deploy_bastion = network.?bastion ?? false
module ccwBastion './bastion.bicep' = if (deploy_bastion) {
  name: 'ccwBastion'
  scope: create_new_vnet ? az.resourceGroup() : az.resourceGroup(split(network.?existing_vnet_id, '/')[4])
  params: {
    location: location
    tags: getTags('Microsoft.Network/bastionHosts', tags)
    subnetId: subnets.bastion.id
  }
}

param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:8.7.120250213'

module ccwVM './vm.bicep' = if (!infrastructureOnly) {
  name: 'ccwVM-cyclecloud'
  params: {
    location: location
    tags: getTags('Microsoft.Compute/virtualMachines', tags)
    networkInterfacesTags: getTags('Microsoft.Network/networkInterfaces', tags)
    name: ccVMName
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
    adminPassword: adminPassword
    databaseAdminPassword: databaseAdminPassword
    adminSshPublicKey: publicKey
    vmSize: ccVMSize
    dataDisks: [
      {
        name: '${ccVMName}-datadisk0'
        disksku: 'Premium_LRS'
        size: split(cyclecloudBaseImage, ':')[0] == 'azurecyclecloud' ? 0 : 128
        caching: 'ReadWrite'
        createOption: split(cyclecloudBaseImage, ':')[0] == 'azurecyclecloud' ? 'FromImage' : 'Empty'
      }
    ]
  }
  dependsOn: [
    ccwNetwork
  ]
}

var miName = 'ccwLockerManagedIdentity'
module ccwManagedIdentity 'mi.bicep' = if (!infrastructureOnly) {
  name: miName
  params: {
    name: miName
    location: location
    storageAccountName: ccwStorage.outputs.storageAccountName
    tags: getTags('Microsoft.ManagedIdentity/userAssignedIdentities', tags)
  }
}

module ccwRoleAssignments './vmRoleAssignments.bicep' = if (!infrastructureOnly) {
  name: 'ccwRoleFor-${ccVMName}-${location}'
  scope: subscription()
  params: {
    roles: [
      'Contributor'
      'Storage Account Contributor'
      'Storage Blob Data Contributor'
    ]
    principalId: ccwVM.outputs.principalId
  }
  dependsOn: [
    ccwVM
  ]
}

module ccwStorage './storage.bicep' = {
  name: 'ccwStorage'
  params: {
    location: location
    tags: getTags('Microsoft.Storage/storageAccounts', tags)
    saName: 'ccwstorage${uniqueString(az.resourceGroup().id)}'
    subnetId: subnets.cyclecloud.id 
  }
}

var create_database = contains(slurmSettings, 'databaseAdminPassword')
var db_name = 'ccw-mysqldb-${uniqueString(az.resourceGroup().id)}'

module mySQLccw './mysql.bicep' = if (create_database) {
  name: 'MySQLDB-ccw'
  params: {
    location: location
    tags: getTags('Microsoft.DBforMySQL/flexibleServers', tags)
    Name: db_name
    adminUser: adminUsername
    adminPassword: databaseAdminPassword
    subnetId: subnets.database.id
  }
}

module ccwAMLFS 'amlfs.bicep' = if (additionalFilesystem.type == 'aml-new') {
  name: 'ccwAMLFS-additional'
  params: {
    location: location
    tags: getTags('Microsoft.StorageCache/amlFileSystems', tags)
    name: 'ccw-lustre'
    subnetId: subnets.?additional.id ?? ''
    sku: additionalFilesystem.?lustreTier
    capacity: additionalFilesystem.?lustreCapacityInTib
    infrastructureOnly: infrastructureOnly
  }
  dependsOn: [
    ccwNetwork
  ]
}

module ccwANFAccount 'anf-account.bicep' = if((sharedFilesystem.type == 'anf-new' || additionalFilesystem.type == 'anf-new') && !infrastructureOnly) {
  name: 'ccwANFAccount'
  params: {
    location: location
  }
}

module ccwANF 'anf.bicep' = [
  for filer in items({ home: sharedFilesystem, additional: additionalFilesystem }): if (filer.value.type == 'anf-new') {
    name: 'ccwANF-${filer.key}'
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
      ccwNetwork
      ccwANFAccount
    ]
  }
]

var deployOOD = ood.type != 'disabled'
var registerOODApp = ood.?registerEntraIDApp ?? false

var oodNicName = 'ccwOpenOnDemandNIC'
module oodNIC 'ood-NIC.bicep' = if (deployOOD) {
  name: oodNicName
  params: {
    location: location
    name: 'ood-${uniqueString(az.resourceGroup().id)}'
    networkInterfacesTags: getTags('Microsoft.Network/networkInterfaces', tags)
    subnetId: subnets.compute.id
  }
}

// create a user assigned managed identity to be assigned to the OOD VM
var oodManagedIdentityName = 'ccwOpenOnDemandManagedIdentity'
resource oodNewManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (registerOODApp) {
  name: oodManagedIdentityName
  location: location
}

var oodAppName = 'CycleCloudOpenOnDemandApp-${uniqueString(az.resourceGroup().id)}'
module oodApp 'ood/oodEntraApp.bicep' = if (registerOODApp) {
  name: 'oodApp'
  params: {
    umiName: oodManagedIdentityName
    appName: oodAppName
    fqdn: oodNIC.outputs.privateIp
  }
}

output filerInfoFinal types.filerInfo_t = {
  home: {
    type: sharedFilesystem.type
    nfsCapacityInGb: sharedFilesystem.?nfsCapacityInGb ?? -1
    ipAddress: sharedFilesystem.type == 'anf-new' ? ccwANF[1].outputs.ipAddress : sharedFilesystem.?ipAddress ?? ''
    exportPath: sharedFilesystem.type == 'anf-new' ? ccwANF[1].outputs.exportPath : sharedFilesystem.?exportPath ?? ''
    mountOptions: sharedFilesystem.type == 'anf-new'
      ? ccwANF[1].outputs.mountOptions
      : sharedFilesystem.?mountOptions ?? ''
    mountPath: '/shared'
  }
  additional: {
    type: additionalFilesystem.type
    ipAddress: additionalFilesystem.type == 'anf-new'
      ? ccwANF[0].outputs.ipAddress
      : additionalFilesystem.type == 'aml-new' ? ccwAMLFS.outputs.ipAddress : additionalFilesystem.?ipAddress ?? ''
    exportPath: additionalFilesystem.type == 'anf-new'
      ? ccwANF[0].outputs.exportPath
      :additionalFilesystem.?exportPath ?? ''
    mountOptions: additionalFilesystem.type == 'anf-new'
      ? ccwANF[0].outputs.mountOptions
      : additionalFilesystem.?mountOptions ?? ''
    mountPath: additionalFilesystem.?mountPath ?? ''
  }
}

output cyclecloudPrincipalId string = infrastructureOnly ? '' : ccwVM.outputs.principalId

output managedIdentityId string = infrastructureOnly ? '' : ccwManagedIdentity.outputs.managedIdentityId

// Automatically inject the ccw and pyxis cluster init specs

var ccwClusterInitSpec = {
  type: 'gitHubReleaseURL'
  gitHubReleaseURL: uri('https://github.com/Azure/cyclecloud-slurm-workspace/releases/tag/', projectVersion)
  spec: 'default'
  target: ['login', 'scheduler', 'htc', 'hpc', 'gpu', 'dynamic']
}

var pyxisClusterInitSpec = {
  type: 'gitHubReleaseURL'
  gitHubReleaseURL: uri('https://github.com/Azure/cyclecloud-pyxis/releases/tag/', pyxisProjectVersion)
  spec: 'default'
  target: ['login', 'scheduler', 'htc', 'hpc', 'gpu', 'dynamic']
}

// Projects <= 2025.02.06 have the pyxis logic embedded in the ccw cluster init spec
var requiredClusterInitSpecs = [ccwClusterInitSpec, pyxisClusterInitSpec]

output clusterInitSpecs types.cluster_init_param_t = union(requiredClusterInitSpecs, clusterInitSpecs)

output slurmSettings types.slurmSettings_t = slurmSettings

output schedulerNode types.scheduler_t = schedulerNode

output loginNodes types.login_t = loginNodes

output partitions types.partitions_t = {
  htc: {
    sku: htc.sku
    maxNodes: htc.maxNodes
    osImage: htc.osImage
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

var acceptedChars = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z','A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z','0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '@', '-', '_']
var clusterNameArr = [for i in range(0, length(clusterName)): substring(clusterName, i, 1)]
var clusterNameArrCleaned = [for c in clusterNameArr: contains(acceptedChars, c) ? c : '_']
var clusterNameCleaned = join(clusterNameArrCleaned,'')

output resourceGroup string = resourceGroup
output location string = location
output storageAccountName string = ccwStorage.outputs.storageAccountName
output clusterName string = clusterNameCleaned
output publicKey string = publicKey
output adminUsername string = adminUsername
output subscriptionId string = subscription().subscriptionId
output tenantId string = subscription().tenantId
// output databaseFQDN string = create_database ? mySQLccw.outputs.fqdn : ''
output databaseInfo types.databaseOutput_t = databaseConfig.type != 'disabled' ?{
  databaseUser: databaseConfig.?databaseUser
  url: databaseConfig.type == 'fqdn' ? databaseConfig.?fqdn : databaseConfig.type == 'privateIp' ? databaseConfig.?privateIp : ccwNetwork.outputs.?databaseFQDN 
} : {}
output azureEnvironment string = envNameToCloudMap[environment().name]
output nodeArrayTags types.tags_t = tags[?'Node Array'] ?? {}

output branch string = branch
output projectVersion string = projectVersion
output insidersBuild bool = insidersBuild
output manualInstall bool = manualInstall
output acceptMarketplaceTerms bool = acceptMarketplaceTerms

output ood object = union(ood, {
  version: '1.0.0'
  nic: deployOOD ? oodNIC.outputs.NICId : ''
  managedIdentity: deployOOD ? registerOODApp ? oodApp.outputs.oodMiId : ood.?appManagedIdentityId : ''
  clientId: deployOOD ? registerOODApp ? oodApp.outputs.oodClientAppId : ood.?appId : ''
  tenantId: deployOOD ? subscription().tenantId : ''
})
