type shared_nfs_new_t = {
  type: 'nfs-new'
  nfsCapacityInGb: int
}

type shared_nfs_existing_t = {
  type: 'nfs-existing'
  ipAddress: string
  exportPath: string
  mountOptions: string?
}

type shared_anf_new_t = {
  type: 'anf-new'
  anfServiceTier: string
  anfCapacityInTiB: int
}

@discriminator('type')
@export()
type sharedFilesystem_t = shared_nfs_new_t | shared_nfs_existing_t | shared_anf_new_t

type additional_anf_new_t = {
  type: 'anf-new'
  anfServiceTier: string
  anfCapacityInTiB: int
  mountPath: string
}

type additional_nfs_existing_t = {
  type: 'nfs-existing'
  ipAddress: string
  mountPath: string
  exportPath: string
  mountOptions: string?
}

type additional_aml_new_t = {
  type: 'aml-new'
  lustreTier: string
  lustreCapacityInTib: int
  mountPath: string
}

type additional_aml_existing_t = {
  type: 'aml-existing'
  ipAddress: string
  mountPath: string
  mountOptions: string?
}

type additional_none_t = {
  type: 'disabled'
}

@discriminator('type')
@export()
type additionalFilesystem_t = additional_anf_new_t | additional_nfs_existing_t | additional_aml_new_t | additional_aml_existing_t | additional_none_t

@export()
type filerInfo_t = {
  home: {
    type: string
    nfsCapacityInGb: int
    ipAddress: string
    exportPath: string
    mountOptions: string
    mountPath: string
  }
  additional: {
    type: string
    ipAddress: string
    exportPath: string
    mountOptions: string
    mountPath: string
  }
}

//note to self: can we make an additional filer type that covers both nfs and aml? 
//we can infer based on the presence of exportPath

type peered_vnet_t = {
  id: string
  location: string
  name: string
}

type vnet_autocreate_t = {
  type: 'new'
  name: string?
  addressSpace: string
  cyclecloudSubnet: string?
  computeSubnet: string?
  sharedFilerSubnet: string?
  additionalFilerSubnet: string?
  bastion: bool?
  createNatGateway: bool?
  vnetToPeer: peered_vnet_t?
  peeringAllowGatewayTransit: bool?
}

type vnet_existing_t = {
  type: 'existing'
  name: string
  id: string
  cyclecloudSubnet: string
  computeSubnet: string
  sharedFilerSubnet: string?
  additionalFilerSubnet: string?
  storagePrivateDnsZoneExists: bool
}

@discriminator('type')
@export()
type vnet_t = vnet_autocreate_t | vnet_existing_t

@export()
type rsc_t = {
  id: string 
  name: string
  rg: string
}

@export()
type networkOutput_t = {
  id: string
  name: string
  rg: string
  type: string
  computeSubnetName: string
  computeSubnetId: string
}

@export()
type subnets_t = {
  cyclecloud: rsc_t
  compute: rsc_t
  home: rsc_t?
  additional: rsc_t?
  bastion: rsc_t?
  database: rsc_t?
}

@export()
type tags_t = {
  *: string
}

@export()
type resource_tags_t = {
  *: tags_t
}

@export()
type slurmSettings_t = {
  version: string
  healthCheckEnabled: bool
}

@export()
type scheduler_t = {
  sku: string
  osImage: string
}

@export()
type login_t = {
  sku: string
  osImage: string
  initialNodes: int
  maxNodes: int
}

@export()
type htc_t = {
  sku: string
  osImage: string
  maxNodes: int
  useSpot: bool?
}

@export()
type htc_output_t = {
  sku: string
  osImage: string
  maxNodes: int
  useSpot: bool
}

@export()
type hpc_t = {
  sku: string
  osImage: string
  maxNodes: int
}

@export()
type partitions_t = {
  htc: htc_output_t
  hpc: hpc_t //if any property becomes optional, create a *_output_t type
  gpu: hpc_t //if any property becomes optional, create a *_output_t type
}

@export()
type storedKey_t = {
  id: string
  location: string
  name: string
}

type db_none_t = {
  type: 'disabled'
}

type db_fqdn_t = {
  type: 'fqdn'
  fqdn: string
}

type db_privateIp_t = {
  type: 'privateIp'
  privateIp: string
}

type dbInfo_t = {
  id: string
  location: string
  name: string
}

type db_privateEndpoint_t = {
  type: 'privateEndpoint'
  dbInfo: dbInfo_t
}

@export()
@discriminator('type')
type databaseConfig_t = db_none_t | db_fqdn_t | db_privateIp_t | db_privateEndpoint_t

@export()
type databaseOutput_t = {
  databaseUser: string?
  url: string?
}

type ood_none_t = {
  type: 'disabled'
}

type ood_enabled_t = {
  type: 'enabled'
  sku: string
  osImage: string
  userDomain: string
  fqdn: string?
  registerEntraIDApp: bool
  appId: string?
  appTenantId: string?
  appManagedIdentityId: string?
}

@export()
@discriminator('type')
type oodConfig_t = ood_none_t | ood_enabled_t
type cluster_init_target_t = 'login' | 'scheduler' | 'htc' | 'hpc' | 'gpu' | 'dynamic' | 'ood'


type github_cluster_init_t = {
  type: 'gitHubReleaseURL'
  gitHubReleaseURL: string
  spec: string?
  target: cluster_init_target_t[]
}

type prestaged_cluster_init_t = {
  type: 'PreStaged'
  spec: string?
  version: string
  target: cluster_init_target_t[]
}

@discriminator('type')
type cluster_init_t = github_cluster_init_t | prestaged_cluster_init_t

@export()
type cluster_init_param_t = cluster_init_t[]?
