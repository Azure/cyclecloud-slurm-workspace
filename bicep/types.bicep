type shared_nfs_new_t = {
  type: 'nfs-new'
  capacity: int
}

type shared_nfs_existing_t = {
  type: 'nfs-existing'
  ip_address: string
  export_path: string
  mount_options: string?
}

type shared_anf_new_t = {
  type: 'anf-new'
  anf_service_tier: string
  anf_capacity_in_bytes: int
}

@discriminator('type')
@export()
type shared_filesystem_t = shared_nfs_new_t | shared_nfs_existing_t | shared_anf_new_t

type additional_anf_new_t = {
  type: 'anf-new'
  anf_service_tier: string
  anf_capacity_in_bytes: int
  mount_path: string
  export_path: string
}

type additional_nfs_existing_t = {
  type: 'nfs-existing'
  ip_address: string
  mount_path: string
  export_path: string
  mount_options: string?
}

type additional_aml_new_t = {
  type: 'aml-new'
  lustre_tier: string
  lustre_capacity_in_tib: int
  mount_path: string
}

type additional_aml_existing_t = {
  type: 'aml-existing'
  ip_address: string
  mount_path: string
  mount_options: string?
}

type additional_none_t = {
  type: 'disabled'
}

@discriminator('type')
@export()
type additional_filesystem_t = additional_anf_new_t | additional_nfs_existing_t | additional_aml_new_t | additional_aml_existing_t | additional_none_t

//note to self: can we make an additional filer type that covers both nfs and aml? 
//we can infer based on the presence of export_path

type peered_vnet_t = {
  id: string
  location: string
  name: string
}

type vnet_autocreate_t = {
  type: 'new'
  name: string?
  address_space: string
  cyclecloudSubnet: string?
  computeSubnet: string?
  sharedFilerSubnet: string?
  additionalFilerSubnet: string?
  bastion: bool?
  create_nat_gateway: bool?
  vnet_to_peer: peered_vnet_t?
  peering_allowGatewayTransit: bool?
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

type inner_tags_t = {
  *: string
}

@export()
type tags_t = {
  *: inner_tags_t
}

@export()
type slurmSettings_t = {
  version: string
  healthCheckEnabled: bool
}

@export()
type scheduler_t = {
  vmSize: string
  image: string
}

@export()
type login_t = {
  vmSize: string
  image: string
  initialNodes: int
  maxNodes: int
}

@export()
type htc_t = {
  vmSize: string
  image: string
  maxNodes: int
  useSpot: bool?
}

@export()
type htc_output_t = {
  vmSize: string
  image: string
  maxNodes: int
  useSpot: bool
}

@export()
type hpc_t = {
  vmSize: string
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
