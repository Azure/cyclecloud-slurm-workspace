targetScope = 'resourceGroup'

param location string = resourceGroup().location
param infrastructureOnly bool

param autogenerateSecrets bool
param useEnteredKey bool 
param useStoredKey bool
param adminUsername string
@secure()
param adminPassword string
param adminSshPublicKey string
param storedKey object = {}

//cc vm parameters
param ccVMSize string

param ccswConfig object
param deploy_scheduler bool = false
@secure()
param databaseAdminPassword string
param branch string
param project_version string
param trash_for_arm_ttk object


var anfDefaultMountOptions = 'rw,hard,rsize=262144,wsize=262144,vers=3,tcp,_netdev'

func getTags(resource_type string, config object) object => (contains(config.tags, resource_type) ? config.tags[resource_type] : {})
//FIX: Autogenerate scenario does not work, see TODO in publicKey.bicep
//TODO 
module ccswPublicKey './publicKey.bicep' = if (!useEnteredKey && !infrastructureOnly) {
  name: 'ccswPublicKey'
  params: {
    location: location
    autogenerateSecrets: autogenerateSecrets
    useStoredKey: useStoredKey
    storedKey: storedKey
  }
}
var publicKey = infrastructureOnly ? '' : (useEnteredKey ? adminSshPublicKey : ccswPublicKey.outputs.publicKey)

var create_nat_gateway = ccswConfig.network.vnet.create_natgateway
module natgateway './natgateway.bicep' = if (create_nat_gateway) {
  name: 'natgateway'
  params: {
    location: location
    tags: getTags('Microsoft.Network/natGateways', ccswConfig)
    name: 'hpc-nat-gateway'
  }
}
var natGateawayId = create_nat_gateway ? natgateway.outputs.NATGatewayId : ''


//FIX: Currently works as expected for creating Vnets for user, but not for BYOV
module ccswNetwork './network-new.bicep' = if(ccswConfig.network.vnet.create){
  name: 'ccswNetwork'
  params: {
    location: location
    tags: getTags('Microsoft.Network/virtualNetworks', ccswConfig)
    nsgTags: getTags('Microsoft.Network/networkSecurityGroups', ccswConfig)
    ccswConfig: ccswConfig
    deploy_scheduler: deploy_scheduler
    natGatewayId: natGateawayId
  }
}

var vnet = ccswConfig.network.vnet.create ? ccswNetwork.outputs.vnet_ccsw : {}
var subnets = ccswConfig.network.vnet.create ? ccswNetwork.outputs.subnets_ccsw : {
  cyclecloud: {id: join([ccswConfig.network.vnet.id, 'subnets', ccswConfig.network.vnet.subnets.cyclecloudSubnet], '/')}
  compute: {id: join([ccswConfig.network.vnet.id, 'subnets', ccswConfig.network.vnet.subnets.computeSubnet], '/')}
  home: {id: join([ccswConfig.network.vnet.id, 'subnets', ccswConfig.network.vnet.subnets.?filerSubnet1 ?? 'null'], '/')}
  additional: {id: join([ccswConfig.network.vnet.id, 'subnets', ccswConfig.network.vnet.subnets.?filerSubnet2 ?? 'null'], '/')}
}

output vnet object = vnet

//TODO re-enable Bastion once security rules determined

var deploy_bastion = ccswConfig.network.vnet.bastion
module ccswBastion './bastion.bicep' = if (deploy_bastion) {
  name: 'ccswBastion'
  scope: createVnet ? resourceGroup() : resourceGroup(split(ccswConfig.network.vnet.id,'/')[4])
  params: {
    location: location
    tags: getTags('Microsoft.Network/bastionHosts', ccswConfig)
    subnetId: subnets.bastion.id
  }
}


param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:8.6.220240605'

var vms = infrastructureOnly ? {cyclecloud: {outputs: {principalId: ''}}} : {
  cyclecloud : {
    //subnetId: subnets.cyclecloud.id
    name: 'ccsw-cyclecloud' //TODO: implement uniqueness
    sku: ccVMSize
    osdisksku: 'StandardSSD_LRS'
    image: {
      plan: 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2'
      ref: contains(cyclecloudBaseImage, '/') ? {
        id: cyclecloudBaseImage
      } : {
        publisher: split(cyclecloudBaseImage,':')[0]
        offer: split(cyclecloudBaseImage,':')[1]
        sku: split(cyclecloudBaseImage,':')[2]
        version: split(cyclecloudBaseImage,':')[3]
      }
    }
    sshPort: 22 //TODO make this configurable
    deploy_script: loadTextContent('./install.sh')
    datadisks: [
      {
        name: 'ccsw-cyclecloud-vm-datadisk0'
        disksku: 'Premium_LRS'
        size: split(cyclecloudBaseImage,':')[0] == 'azurecyclecloud' ? 0 : 128
        caching: 'ReadWrite'
        createOption: split(cyclecloudBaseImage,':')[0] == 'azurecyclecloud' ? 'FromImage' : 'Empty'
      }
    ]
    identity: {
      keyvault: {
        secret_permissions: [ 'All' ]
      } 
      roles: [
        'Contributor','Storage Account Contributor','Storage Blob Data Contributor'
      ]
    }
  }
}

module ccswVM './vm.bicep' = [ for vm in items(vms): if (!infrastructureOnly) {
  name: 'ccswVM-${vm.key}'
  params: {
    location: location
    tags: getTags('Microsoft.Compute/virtualMachines', ccswConfig)
    networkInterfacesTags: getTags('Microsoft.Network/networkInterfaces', ccswConfig)
    name: vm.value.name 
    vm: vm.value
    image: vm.value.image
    subnetId: vm.value.name == 'ccsw-cyclecloud' ? subnets.cyclecloud.id : subnets.scheduler.id
    adminUser: adminUsername
//    adminPassword: adminPassword // Not used in the module
    adminSshPublicKey: publicKey
//    asgIds: {}
  }
  dependsOn: [
    ccswNetwork
  ]
}]

module ccswRolesAssignments './roleAssignments.bicep' = [ for vm in items(vms): if (contains(vm.value, 'identity') && contains(vm.value.identity, 'roles')) {
  name: 'ccswRoleFor-${vm.key}-${location}'
  scope: subscription()
  params: {
    name: vm.key
    rgID: resourceGroup().id
    roles: vm.value.identity.roles
    principalId: ccswVM[indexOf(map(items(vms), item => item.key), vm.key)].outputs.principalId
  }
  dependsOn: [
    ccswVM
  ]
}]

module ccswStorage './storage.bicep' = {
  name: 'ccswStorage'
  params:{
    location: location
    tags: getTags('Microsoft.Storage/storageAccounts', ccswConfig)
    saName: 'ccswstorage${uniqueString(resourceGroup().id)}'
    lockDownNetwork: true // Restrict access to the storage account from compute and cyclecloud subnets
    subnetIds: concat([subnets.compute.id], [subnets.cyclecloud.id])
  }
}

var create_database = ccswConfig.slurm_settings.scheduler_node.slurmAccounting
var db_name = 'hpc-mysqldb-${uniqueString(resourceGroup().id)}'
var db_password = databaseAdminPassword

module mySQLccsw './mysql.bicep' = if (create_database) {
  name: 'mySQLDB-ccsw'
  params: {
    location: location
    tags: getTags('Microsoft.DBforMySQL/flexibleServers', ccswConfig)
    Name: db_name
    adminUser: adminUsername
    adminPassword: db_password
    subnetId: subnets.database.id //TODO change for BYOVnet scenario
  }
}

var createVnet = ccswConfig.network.vnet.create

var filer_info = {
  home: union({
    use: true
    create_new: ccswConfig.filesystem.shared.create_new
  }, ccswConfig.filesystem.shared.config)
  additional: union({
    use: ccswConfig.filesystem.?additional.?additional_filer ?? false
    create_new: ccswConfig.filesystem.?additional.?create_new ?? false
  }, ccswConfig.filesystem.?additional.?config ?? {})
}


//TODO: Make Lustre work with filer_info object
var addl_filer_is_lustre = contains(ccswConfig.filesystem.?additional.?config ?? {}, 'filertype') && ccswConfig.filesystem.additional.config.filertype == 'aml'

//only use first set of Lustre settings configured by the user 
var lustre_info = addl_filer_is_lustre ? union(
      {subnet_name: (createVnet ? 'hpc-lustre-subnet' : ccswConfig.network.vnet.subnets.filerSubnet2)},
      {config: {
        create_new: ccswConfig.filesystem.?additional.?create_new ?? false
        sku: ccswConfig.filesystem.?additional.?config.?lustre_tier ?? ''
        capacity: int(ccswConfig.filesystem.?additional.?config.?lustre_capacity_in_tib ?? 0)
        filer: 'additional'
        export_path: ccswConfig.filesystem.?additional.?config.?export_path ?? ''
        }
      }
    ) : null

module ccswAMLFS 'amlfs.bicep' = [ for lustre in [lustre_info]: if (lustre != null && lustre.?config.?create_new) {
  name: 'ccswAMLFS-${lustre!.?config.?filer}'
  params: {
    location: location
    tags: getTags('Microsoft.StorageCache/amlFileSystems', ccswConfig)
    name: 'hpc-lustre'
    subnetId: subnets.additional.id
    sku: lustre!.config.sku
    capacity: lustre!.config.capacity
    infrastructureOnly: infrastructureOnly
    exportPath: lustre!.config.export_path
  }
  dependsOn: [
    ccswNetwork
  ]
}]

type existing_filer_t = {
  name: string
  outputs: {
    ip_address: {
      value: string
    }
    export_path: {
      value: string
    }
    mount_options: {
      value: string
    }
  }
}

var emptyExistingFiler = {
  name: 'null'
  outputs: {
    ip_address: {value: 'null'}
    export_path: {value: 'null'}
    mount_options: {value: 'null'}
  }
}
output emptyExistingFiler existing_filer_t = emptyExistingFiler

var ccswAMLFSExisting = (lustre_info != null && !lustre_info!.config.create_new ?? true)  ? {
  name: 'ccswAMLFS-additional'
  outputs: {
    ip_address: {value: filer_info.additional.ip_address}
    export_path: {value: ''}
    mount_options: {value: lustre_info.?mount_options ?? ''}
  }
} : emptyExistingFiler


module ccswANF 'anf.bicep' = [ for filer in items(filer_info): if (filer.value.use && filer.value.create_new && filer.value.filertype == 'anf') {
  name: 'ccswANF-${filer.key}'
  params: {
    location: location
    tags: getTags('Microsoft.NetApp/netAppAccounts', ccswConfig)
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
}]

// Duck typing for existing filers - make them have the same attributes as a filer module

var ccswANFExistingHome = (!filer_info.home.create_new && filer_info.home.filertype == 'anf' ? {
  name: 'ccswANF-home'
  outputs: {
    ip_address: {value: filer_info.home.ip_address}
    export_path: {value: filer_info.home.export_path}
    mount_options: {value: (filer_info.home.?mount_options ?? '') == '' ? anfDefaultMountOptions : filer_info.home.mount_options}
  }
} : emptyExistingFiler)

var ccswANFExistingAdditional = (!filer_info.additional.create_new && filer_info.additional.filertype == 'anf' ? {
  name: 'ccswANF-additional'
  outputs: {
    ip_address: filer_info.additional.ip_address
    export_path: filer_info.additional.?export_path ?? ''
    mount_options: (filer_info.additional.?mount_options ?? '') == '' ? anfDefaultMountOptions : filer_info.additional.mount_options
  }
} : emptyExistingFiler)

// TODO hack for type checking.
output ccswANFExistingHome existing_filer_t = ccswANFExistingHome
output ccswAMLFSExisting existing_filer_t = ccswAMLFSExisting
output ccswANFExistingAdditional existing_filer_t = ccswANFExistingAdditional


// NOTE: in ANF deployment loops, the bicep items() function alphabetizes the language elements of filer_info (i.e., index 0 references 'additional' and 1 references 'home' below)
// Note we use duck typing here - each module has the same expected outputs - ip_address, export_path and mount_options.
var is_home_anf = filer_info.home.filertype == 'anf'
var is_home_new = filer_info.home.create_new
var fs_module_home = is_home_anf ? (is_home_new ? ccswANF[1] : ccswANFExistingHome) : null

var is_addl_new = filer_info.additional.?create_new ?? false
var is_addl_anf = filer_info.?additional.?filertype == 'anf'
var is_addl_aml = filer_info.?additional.?filertype == 'aml'
var fs_module_additional = is_addl_anf ? (is_addl_new ? ccswANF[0] : ccswANFExistingAdditional) : (is_addl_aml ? (is_addl_new ? ccswAMLFS[0] : ccswAMLFSExisting) : null)

type filertype_t = 'anf' | 'aml' | 'nfs' | ''
type filer_settings_t = {
  use: bool
  create_new: bool
  filertype: filertype_t
  nfs_capacity_in_gb: int
  ip_address: string
  export_path: string
  mount_options: string
  mount_path: string
}

type filer_info_t = {
  home: filer_settings_t
  additional: filer_settings_t
}

var filer_info_final = {
  home: {
    use: true
    create_new: filer_info.home.create_new
    filertype: filer_info.home.filertype
    nfs_capacity_in_gb: filer_info.home.nfs_capacity_in_gb
    // note the fs_module_home! - it really can't be null, but the linter does not handle the
    // ternary with a null properly
    ip_address: fs_module_home == null ? filer_info.home.ip_address : fs_module_home!.outputs.ip_address.value
    export_path: fs_module_home == null ? filer_info.home.export_path : fs_module_home!.outputs.export_path.value
    mount_options: fs_module_home == null ? filer_info.home.mount_options : fs_module_home!.outputs.mount_options.value
    mount_path: '/shared'
  }
  additional: { 
    use: ccswConfig.filesystem.?additional.additional_filer ?? false
    create_new: filer_info.?additional.?create_new ?? false
    filertype: filer_info.?additional.?filertype
    nfs_capacity_in_gb: filer_info.?additional.?nfs_capacity_in_gb ?? 0
    ip_address: fs_module_additional == null ? filer_info.?additional.?ip_address : fs_module_additional!.outputs.ip_address.value
    export_path: fs_module_additional == null ? filer_info.?additional.?export_path : fs_module_additional!.outputs.export_path.value
    mount_options: fs_module_additional == null ? filer_info.?additional.?mount_options : fs_module_additional!.outputs.mount_options.value
    mount_path: filer_info.?additional.?mount_path
  }
}
output filer_info_final filer_info_t = filer_info_final


output cyclecloudPrincipalId string = infrastructureOnly ? '' : ccswVM[0].outputs.principalId

output ccswConfig object = ccswConfig

var envNameToCloudMap = {
  AzureCloud: 'AZUREPUBLICCLOUD'
  AzureUSGovernment: 'AZUREUSGOVERNMENT'
  AzureGermanCloud: 'AZUREGERMANCLOUD'
  AzureChinaCloud: 'AZURECHINACLOUD'
}
var pword = split('foo-${adminPassword}-foo','-')[1] //workaround linter & arm-ttk

//FIX: remove old comments and clean up
output ccswGlobalConfig object = union(
  {
    global_cc_storage             : ccswStorage.outputs.storageAccountName
    compute_subnetid              : subnets.compute.id
    publicKey                     : publicKey
    adminUsername                 : adminUsername
    adminPassword                 : pword
    homedir_mountpoint            : '/nfshome' //FIX cribbed from AzHop, unsure if correct
    subscription_id               : subscription().subscriptionId
    tenant_id                     : subscription().tenantId
    lustre_hsm_storage_account    : ccswStorage.outputs.storageAccountName
    lustre_hsm_storage_container  : 'lustre'
    database_fqdn                 : create_database ? mySQLccsw.outputs.fqdn : ''
    database_user                 : adminUsername
    azure_environment             : envNameToCloudMap[environment().name]
    blob_storage_suffix           : 'blob.${environment().suffixes.storage}' // blob.core.windows.net
  },
  {}
)

output trash object = trash_for_arm_ttk
output branch string = branch
output project_version string = project_version
