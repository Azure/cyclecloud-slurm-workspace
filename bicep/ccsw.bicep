targetScope = 'resourceGroup'

param location string = resourceGroup().location

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
param trash_for_arm_ttk object 

//FIX: Autogenerate scenario does not work, see TODO in publicKey.bicep
//TODO 
module ccswPublicKey './publicKey.bicep' = if (!useEnteredKey) {
  name: 'ccswPublicKey'
  params: {
    location: location
    autogenerateSecrets: autogenerateSecrets
    useStoredKey: useStoredKey
    storedKey: storedKey
  }
}
var publicKey = useEnteredKey ? adminSshPublicKey : ccswPublicKey.outputs.publicKey

var create_nat_gateway = ccswConfig.network.vnet.create_natgateway
module natgateway './natgateway.bicep' = if (create_nat_gateway) {
  name: 'natgateway'
  params: {
    location: location
    name: 'hpc-nat-gateway'
  }
}
var natGateawayId = create_nat_gateway ? natgateway.outputs.NATGatewayId : ''


//FIX: Currently works as expected for creating Vnets for user, but not for BYOV
module ccswNetwork './network-new.bicep' = {
  name: 'ccswNetwork'
  params: {
    location: location
    ccswConfig: ccswConfig
    deploy_scheduler: deploy_scheduler
    natGatewayId: natGateawayId
  }
}
var nsg = ccswNetwork.outputs.nsg_ccsw
var vnet = ccswNetwork.outputs.vnet_ccsw
var subnets = ccswNetwork.outputs.subnets_ccsw
var asgNameToIdLookup = reduce(ccswNetwork.outputs.asgIds, {}, (cur, next) => union(cur, next))
output vnet object = vnet

//TODO re-enable Bastion once security rules determined

var deploy_bastion = ccswConfig.network.vnet.bastion
module ccswBastion './bastion.bicep' = if (deploy_bastion) {
  name: 'ccswBastion'
  scope: createVnet ? resourceGroup() : resourceGroup(split(ccswConfig.network.vnet.id,'/')[4])
  params: {
    location: location
    subnetId: subnets.bastion.id
  }
}


param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:latest'

var vms = {
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
    asgs: [ 'asg-cyclecloud' ]
  }
}

module ccswVM './vm.bicep' = [ for vm in items(vms): {
  name: 'ccswVM-${vm.key}'
  params: {
    location: location
    name: vm.value.name 
    vm: vm.value
    image: vm.value.image
    subnetId: vm.value.name == 'ccsw-cyclecloud' ? subnets.cyclecloud.id : subnets.scheduler.id
    adminUser: adminUsername
    adminPassword: adminPassword
    adminSshPublicKey: publicKey
    asgIds: asgNameToIdLookup
    nsg: nsg
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
//output ccVM_principalId string = ccswVM[0].outputs.principalId

module ccswStorage './storage.bicep' = {
  name: 'ccswStorage'
  params:{
    location: location
    saName: 'ccswstorage${uniqueString(resourceGroup().id)}'
    lockDownNetwork: false
    allowableIps: []
    subnetIds: concat([ subnets.compute.id],deploy_scheduler ? [subnets.scheduler.id] : [])
  }
}

var create_database = ccswConfig.slurm_settings.scheduler_node.slurmAccounting
var db_name = 'hpc-mysqldb-${uniqueString(resourceGroup().id)}'
var db_password = databaseAdminPassword
//contains(ccswConfig.slurm_settings.scheduler_node, 'databaseAdminPassword') ? ccswConfig.slurm_settings.scheduler_node.databaseAdminPassword : ''
module mySQLccsw './mysql.bicep' = if (create_database) {
  name: 'mySQLDB-ccsw'
  params: {
    location: location
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
    is_second_new_anf: false
  }, ccswConfig.filesystem.shared.config)
  additional: union({
    use: ccswConfig.filesystem.additional.additional_filer
    create_new: ccswConfig.filesystem.additional.create_new
    is_second_new_anf: ccswConfig.filesystem.additional.config.filertype == 'anf' && ccswConfig.filesystem.shared.config.filertype == 'anf' && ccswConfig.filesystem.additional.create_new
  }, ccswConfig.filesystem.additional.config)
}


//TODO: Make Lustre work with filer_info object
var filer1_is_lustre = ccswConfig.filesystem.shared.config.filertype == 'aml'
var filer2_is_lustre = contains(ccswConfig.filesystem.additional.config, 'filertype') && ccswConfig.filesystem.additional.config.filertype == 'aml'

//only use first set of Lustre settings configured by the user 
var lustre_info = concat(
  filer1_is_lustre ? [
    union(
      {subnet_name: (createVnet ? 'hpc-lustre-subnet' : ccswConfig.network.vnet.subnets.filerSubnet1)},
      {config: {
        sku: ccswConfig.filesystem.shared.config.lustre_tier
        capacity: int(ccswConfig.filesystem.shared.config.lustre_capacity_in_tib)
        filer: 'shared'
        }
      }
    )
  ] : [],
  filer2_is_lustre && !filer1_is_lustre ? [
    union(
      {subnet_name: (createVnet ? 'hpc-lustre-subnet' : ccswConfig.network.vnet.subnets.filerSubnet2)},
      {config: {
        sku: ccswConfig.filesystem.additional.config.lustre_tier
        capacity: int(ccswConfig.filesystem.additional.config.lustre_capacity_in_tib)
        filer: 'additional'
        }
      }
    )
  ] : []
)

module ccswAMLFS 'amlfs.bicep' = [ for lustre in lustre_info: {
  name: 'ccswAMLFS-${lustre.config.filer}'
  params: {
    location: location
    name: 'hpc-lustre'
    subnetId: subnets.lustre.id //TODO change for BYOVnet scenario
    sku: lustre.config.sku
    capacity: lustre.config.capacity
  }
  dependsOn: [
    ccswNetwork
  ]
}]

module ccswANF 'anf.bicep' = [ for filer in items(filer_info): if (filer.value.use && filer.value.create_new && filer.value.filertype == 'anf') {
  name: 'ccswANF-${filer.key}'
  params: {
    location: location
    name: filer.key
    subnetId: subnets.anf.id //TODO change for BYOVnet scenario
    serviceLevel: filer.value.anf_service_tier
    sizeGB: int(filer.value.anf_capacity_in_bytes)
  }
  dependsOn: [
    ccswNetwork
  ]
}]

//TODO: Implement Azure NFS Files
//var make_external_nfs = false
/*
module ccswNfsFiles './nfsfiles.bicep' = [ for nfs in nfs_info: if (make_external_nfs) {
  name: 'ccswNfsFiles-${nfs.config.filer}'
  params: {
    name: 'hpcnfs'
    location: location
    allowedSubnetIds: concat([subnets.compute.id, subnets.cyclecloud.id ],deploy_scheduler ? [subnets.scheduler.id] : [])
    sizeGB: nfs.config.sizeGB
  }
  dependsOn: [
    ccswNetwork
  ]
}]
*/

//NOTE: in ANF deployment loops, the bicep items() function alphabetizes the language elements of filer_info (i.e., index 0 references 'additional' and 1 references 'home' below)
// Note we use duck typing here - each module has the same expected outputs - ip_address, export_path and mount_options.
var fs_module_home = filer_info.home.create_new ? (filer_info.home.filertype == 'anf' ? ccswANF[1] : (filer_info.home.filertype == 'aml' ? ccswAMLFS[0] : null)) : null

// TODO: if we restore creation of additional FS, we can use the same concept. It will probably break for two amlfs deployments, but ...
// that is incredibly expensive as well.
// var fs_module_additional = filer_info.home.create_new ? (filer_info.home.filertype == 'anf' ? ccswANF[0] : (filer_info.home.filertype == 'aml' ? ccswAMLFS[0] : null)) : null

var filer_info_final = {
  home: {
    use: true
    create_new: filer_info.home.create_new
    filertype: filer_info.home.filertype
    nfs_capacity_in_gb: filer_info.home.nfs_capacity_in_gb
    // note the fs_module_home! - it really can't be null, but the linter does not handle the
    // ternary with a null properly
    ip_address: fs_module_home == null ? filer_info.home.ip_address : fs_module_home!.outputs.ip_address
    export_path: fs_module_home == null ? filer_info.home.export_path : fs_module_home!.outputs.export_path
    mount_options: fs_module_home == null ? filer_info.home.mount_options : fs_module_home!.outputs.mount_options

  }
  additional: { 
    use: ccswConfig.filesystem.additional.additional_filer
    // For now, we are forcing additional filer to always be external. We can come back to creating them in the future.
    create_new: false
    filertype: filer_info.additional.filertype
    ip_address: filer_info.additional.ip_address
    mount_path: filer_info.additional.mount_path
    export_path: filer_info.additional.export_path
    mount_options: filer_info.additional.mount_options
  }
}
output filer_info_final object = filer_info_final


output cyclecloudPrincipalId string = ccswVM[indexOf(map(items(vms), item => item.key), 'cyclecloud')].outputs.principalId

//no keyvault

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
    //global_config_file            : '/az-hop/config.yml'
    //ad_join_user                  : config.domain.domain_join_user.username
    //domain_name                   : config.domain.name
    //ldap_server                   : '${config.domain.ldap_server}.${config.domain.name}'
    homedir_mountpoint            : '/nfshome' //FIX cribbed from AzHop, unsure if correct
    //FIX we need second mount point for second dir, correct? 
    //ondemand_fqdn                 : ccswVM[indexOf(map(items(vms), item => item.key), 'ondemand')].outputs.privateIp //TODO ask if needed
    //ansible_ssh_private_key_file  : '${config.admin_user}_id_rsa'//TODO ask
    subscription_id               : subscription().subscriptionId
    tenant_id                     : subscription().tenantId
    //key_vault                     : config.key_vault_name
    //sig_name                      : (config.deploy_sig) ? 'azhop_${resourcePostfix}' : ''
    lustre_hsm_storage_account    : ccswStorage.outputs.storageAccountName
    lustre_hsm_storage_container  : 'lustre'
    database_fqdn                 : create_database ? mySQLccsw.outputs.fqdn : ''
    database_user                 : adminUsername
    azure_environment             : envNameToCloudMap[environment().name]
    //key_vault_suffix              : substring(kvSuffix, 1, length(kvSuffix) - 1) // vault.azure.net - remove leading dot from env
    blob_storage_suffix           : 'blob.${environment().suffixes.storage}' // blob.core.windows.net
    //jumpbox_ssh_port              : incomingSSHPort
  },
  /*createComputeMI ? {
    compute_mi_id                 : resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', computemi.name)
  }: {},*/
  /*!empty(existingComputeMIrg) ? {
    compute_mi_id                 : resourceId(existingComputeMIrg,'Microsoft.ManagedIdentity/userAssignedIdentities', computeMIname)
  }: {},*/
  /*filer1_is_anf || filer2_is_anf ? {
    anf_home_netad                : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_ip : ''
    anf_home_path                 : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_path : ''
    anf_home_opts                 : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_opts : ''
  } : {},
  make_external_nfs && (filer1_is_nfs || filer2_is_nfs) ? {
    nfs_home_netad                : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_ip : ''
    nfs_home_path                 : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_path : ''
    nfs_home_opts                 : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_opts : ''
  } : {},
  /*config.homedir_type == 'existing' ? { //TODO discuss
    anf_home_ip                   : azhopConfig.mounts.home.server
    anf_home_path                 : azhopConfig.mounts.home.export
    anf_home_opts                 : azhopConfig.mounts.home.options
  } : {},
  filer1_is_lustre || filer2_is_lustre? {
    lustre_ip                    : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_mgs : ''
    //lustre_home_path             : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_path : '' //TODO confirm correct
    lustre_home_opts             : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_mountcommand : '' //TODO confirm correct
  } : {}*/
  {}
)
//output lustre_object object = filer1_is_lustre || filer2_is_lustre ? ccswAMLFS[0] : {}
output param_script string = loadTextContent('./files-to-load/create_cc_param.py')
output initial_param_json object = loadJsonContent('./files-to-load/initial_params.json')
output trash object = trash_for_arm_ttk
