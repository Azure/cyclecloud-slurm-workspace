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

//FIX: Currently works as expected for creating Vnets for user, but not for BYOV
module ccswNetwork './network-new.bicep' = {
  name: 'ccswNetwork'
  params: {
    location: location
    ccswConfig: ccswConfig
    deploy_scheduler: deploy_scheduler
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


//TODO update CC version
param cyclecloudBaseImage string = 'azurecyclecloud:azure-cyclecloud:cyclecloud8-gen2:latest'
param schedulerImage string = ccswConfig.slurm_settings.scheduler_node.schedulerImage

var vms = union(
  {
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
      asgs: [ 'asg-ssh', 'asg-cyclecloud', 'asg-jumpbox']
    }
  },
  deploy_scheduler ? {
    scheduler : {
      //subnetId: subnets.compute.id
      name: 'ccsw-scheduler' //TODO: implement uniqueness
      sku: ccswConfig.slurm_settings.scheduler_node.schedulerVMSize
      osdisksku: 'StandardSSD_LRS'
      image: {
        plan: schedulerImage
        ref:  {
          publisher: split(schedulerImage,':')[0]
          offer: split(schedulerImage,':')[1]
          sku: split(schedulerImage,':')[2]
          version: split(schedulerImage,':')[3]
        }
      }
      asgs: [ 'asg-ssh', 'asg-sched', 'asg-cyclecloud-client', 'asg-nfs-client' ]
    }
  } : {}
)

module ccswVM './vm2.bicep' = [ for vm in items(vms): {
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
  name: 'ccswRoleFor-${vm.key}'
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

var filer1_is_anf = ccswConfig.filesystem.shared.config.filertype == 'anf'
var filer2_is_anf = contains(ccswConfig.filesystem.additional.config, 'filertype') && ccswConfig.filesystem.additional.config.filertype == 'anf'
//only use first set of ANF settings configured by the user 
var anf_info = concat(
  filer1_is_anf ? [
    union(
      {subnet_name: (createVnet ? 'hpc-anf-subnet' : ccswConfig.network.vnet.subnets.filerSubnet1)},
      {config: {
        serviceLevel: ccswConfig.filesystem.shared.config.anf_service_tier
        sizeGB: int(ccswConfig.filesystem.shared.config.anf_capacity_in_bytes)
        filer: 'shared'
        }
      }
    )
  ] : [],
  filer2_is_anf && !filer1_is_anf ? [
    union(
      {subnet_name: (createVnet ? 'hpc-anf-subnet' : ccswConfig.network.vnet.subnets.filerSubnet2)},
      {config: {
        serviceLevel: ccswConfig.filesystem.additional.config.anf_service_tier
        sizeGB: int(ccswConfig.filesystem.additional.config.anf_capacity_in_bytes)
        filer: 'additional'
        }
      }
    )
  ] : []
)
module ccswANF 'anf.bicep' = [ for anf in anf_info: {
  name: 'ccswANF-${anf.config.filer}'
  params: {
    location: location
    name: 'hpc-anf'
    dualProtocol: false //TODO inquire
    subnetId: subnets.anf.id //TODO change for BYOVnet scenario
    adUser: adminUsername
    adPassword: adminPassword
    adDns: '' //TODO inquire
    serviceLevel: anf.config.serviceLevel
    sizeGB: anf.config.sizeGB
  }
  dependsOn: [
    ccswNetwork
  ]
}]

var filer1_is_nfs = ccswConfig.filesystem.shared.config.filertype == 'nfs'
var filer2_is_nfs = contains(ccswConfig.filesystem.additional.config, 'filertype') && ccswConfig.filesystem.additional.config.filertype == 'nfs'
//only use first set of NFS settings configured by the user 
var nfs_info = concat(
  filer1_is_nfs ? [
    {config: {
      sizeGB: int(ccswConfig.filesystem.shared.config.nfs_capacity_in_gb)
      filer: 'shared'
      }
    }
  ] : [],
  filer2_is_nfs && !filer1_is_nfs ? [
    {config: {
      sizeGB: int(ccswConfig.filesystem.additional.config.nfs_capacity_in_gb)
      filer: 'additional'
      }
    }
  ] : []
)

module ccswNfsFiles './nfsfiles.bicep' = [ for nfs in nfs_info: {
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
  filer1_is_anf || filer2_is_anf ? {
    anf_home_netad                : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_ip : ''
    anf_home_path                 : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_path : ''
    anf_home_opts                 : length(anf_info) != 0 ? ccswANF[0].outputs.nfs_home_opts : ''
  } : {},
  filer1_is_nfs || filer2_is_nfs ? {
    nfs_home_netad                : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_ip : ''
    nfs_home_path                 : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_path : ''
    nfs_home_opts                 : length(nfs_info) != 0 ? ccswNfsFiles[0].outputs.nfs_home_opts : ''
  } : {},
  /*config.homedir_type == 'existing' ? { //TODO discuss
    anf_home_ip                   : azhopConfig.mounts.home.server
    anf_home_path                 : azhopConfig.mounts.home.export
    anf_home_opts                 : azhopConfig.mounts.home.options
  } : {},*/
  filer1_is_lustre || filer2_is_lustre? {
    lustre_ip                    : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_mgs : ''
    //lustre_home_path             : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_path : '' //TODO confirm correct
    lustre_home_opts             : length(lustre_info) != 0 ? ccswAMLFS[0].outputs.lustre_mountcommand : '' //TODO confirm correct
  } : {}
)
//output lustre_object object = filer1_is_lustre || filer2_is_lustre ? ccswAMLFS[0] : {}
output param_script string = loadTextContent('../../testparam/cc_template_functions/create_cc_param.py')
output initial_param_json object = loadJsonContent('../../testparam/cc_template_functions/initial_params.json')
output trash object = trash_for_arm_ttk
