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
  anfCapacityInBytes: int
}

@discriminator('type')
@export()
type sharedFilesystem_t = shared_nfs_new_t | shared_nfs_existing_t | shared_anf_new_t

type additional_anf_new_t = {
  type: 'anf-new'
  anfServiceTier: string
  anfCapacityInBytes: int
  mountPath: string
  exportPath: string
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
}

@discriminator('type')
@export()
type vnet_t = vnet_autocreate_t | vnet_existing_t

@export()
type rsc_t = {
  id: string 
  name: string
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
  image: string
}

@export()
type login_t = {
  sku: string
  image: string
  initialNodes: int
  maxNodes: int
}

@export()
type htc_t = {
  sku: string
  image: string
  maxNodes: int
  useSpot: bool?
}

@export()
type htc_output_t = {
  sku: string
  image: string
  maxNodes: int
  useSpot: bool
}

@export()
type hpc_t = {
  sku: string
  image: string
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
