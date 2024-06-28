param address string = ccswConfig.network.vnet.address_space
param location string
param tags object
param nsgTags object
param ccswConfig object

param create_anf bool = ccswConfig.filesystem.shared.config.filertype == 'anf' || (contains(ccswConfig.filesystem.?additional.?config ?? {},'filertype') && ccswConfig.filesystem.additional.config.filertype == 'anf')
param lustre_count int = (ccswConfig.filesystem.shared.config.filertype == 'aml' ? 1 : 0) + ((contains(ccswConfig.filesystem.?additional.?config ?? {},'filertype') && ccswConfig.filesystem.additional.config.filertype == 'aml') ? 1 : 0)
param create_lustre bool = lustre_count > 0
param deploy_bastion bool = ccswConfig.network.vnet.bastion
param create_database bool = ccswConfig.slurm_settings.scheduler_node.slurmAccounting
param deploy_scheduler bool
param natGatewayId string 

//TODO rename function, see if using exp/0 to throw error is possible 
func pow2_or_0 (exp int) int => 
  (exp == -1) ? 0 : (exp == 0) ? 1 : (exp == 1) ? 2 : (exp == 2) ? 4 : (exp == 3) ? 8 : -1000

func decompose_ip(ip string) object => {
  o1: int(split(split(ip,'/')[0],'.')[0])
  o2: int(split(split(ip,'/')[0],'.')[1])
  o3: int(split(split(ip,'/')[0],'.')[2])
  o4: int(split(split(ip,'/')[0],'.')[3])
}

func get_cidr(ip string) int => int(split(ip,'/')[1])

func subnet_octets(cidr int) object => {
  cyclecloud: { //cyclecloud
    o3: 0
    o4: 0
    cidr: 29
  }
  scheduler: { //admin
    o3: 0
    o4: 16
    cidr: 28
  }
  netapp: {
    o3: 0
    o4: 32
    cidr: (cidr == 24) ? 29 : 28
  }
  bastion: {
    o3: 0
    o4: 64
    cidr: 26
  }
  lustre: {
    o3: 0
    o4: (cidr == 24) ? 48 : 128
    cidr: (cidr == 24) ? 28 : 26
  }
  database: {
    o3: 0
    o4: (cidr == 24) ? 40 : 224
    cidr: (cidr == 24) ? 29 : 28
  }
  compute: {
    o3: pow2_or_0(23-cidr)
    o4: (cidr == 24) ? 128 : 0
    cidr: cidr+1
  }
}

func subnet_ranges(decomp_ip object, subnet object) object => {
  cyclecloud: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.cyclecloud.o3}.${decomp_ip.o4+subnet.cyclecloud.o4}/${subnet.cyclecloud.cidr}'
  scheduler: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.scheduler.o3}.${decomp_ip.o4+subnet.scheduler.o4}/${subnet.scheduler.cidr}'
  netapp: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.netapp.o3}.${decomp_ip.o4+subnet.netapp.o4}/${subnet.netapp.cidr}'
  bastion: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.bastion.o3}.${decomp_ip.o4+subnet.bastion.o4}/${subnet.bastion.cidr}'
  lustre: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.lustre.o3}.${decomp_ip.o4+subnet.lustre.o4}/${subnet.lustre.cidr}'
  database: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.database.o3}.${decomp_ip.o4+subnet.database.o4}/${subnet.database.cidr}'
  compute: '${decomp_ip.o1}.${decomp_ip.o2}.${decomp_ip.o3+subnet.compute.o3}.${decomp_ip.o4+subnet.compute.o4}/${subnet.compute.cidr}'
}

func subnet_config(ip string, lustre_count int) object => subnet_ranges(decompose_ip(ip),subnet_octets(get_cidr(ip)))

param subnet_cidr object = subnet_config(address,lustre_count)

param vnet object = {
  name: ccswConfig.network.vnet.name
  cidr: address
  subnets: union(
    {
      cyclecloud: {
        name: ccswConfig.network.vnet.subnets.cyclecloudSubnet
        cidr: subnet_cidr.cyclecloud
        nat_gateway: true
        service_endpoints: [
          'Microsoft.Storage'
        ]
        delegations: []
      }
      compute: {
        name: ccswConfig.network.vnet.subnets.computeSubnet
        cidr: subnet_cidr.compute
        nat_gateway : true 
        service_endpoints: [
          'Microsoft.Storage'
        ]
        delegations: []
      }
    },
    deploy_scheduler ? {
      scheduler: {
        name: ccswConfig.network.vnet.subnets.schedulerSubnet
        cidr: subnet_cidr.scheduler
        nat_gateway : true
        service_endpoints: [
          'Microsoft.Storage'
        ]
        delegations: []
      } 
    } : {},
    create_anf ? {
      netapp: {
        name: 'hpc-anf-subnet'
        cidr: subnet_cidr.netapp
        nat_gateway : false
        service_endpoints: []
        delegations: [
          'Microsoft.Netapp/volumes'
        ]
      }
    } : {},
    create_lustre ? {
      lustre: {
        name: 'hpc-lustre-subnet'
        cidr: subnet_cidr.lustre
        nat_gateway : false
        service_endpoints: []
        delegations: []
      }
    } : {},
    deploy_bastion ? {
      bastion: {
        name: 'AzureBastionSubnet'
        cidr: subnet_cidr.bastion
        nat_gateway : false
        service_endpoints: []
        delegations: []
      }
    } : {},
    create_database ? {
      database: {
        name: 'hpc-database-subnet'
        cidr: subnet_cidr.database
        nat_gateway : false
        service_endpoints: []
        delegations: [
          'Microsoft.DBforMySQL/flexibleServers'
        ]
      }
    } : {}
  )
}
//TODO review NSG rules with Ben and Xavier
var nsg_rules = {
  default: {
    //
    // INBOUND RULES
    //
    // Allow https incoming connections
    AllowHttpsIn: ['100', 'Inbound', 'Allow', 'Tcp', 'Https', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    // Allow ssh from cyclecloud to compute
    AllowSshCyclecloudComputeIn: ['200', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'subnet', 'cyclecloud', 'subnet', 'compute']

    // All communications inside compute subnet
    AllowAllComputeComputeIn: ['365', 'Inbound', 'Allow', 'Tcp', 'All', 'subnet', 'compute', 'subnet', 'compute']

    // CycleCloud
    AllowCycleClientComputeIn: ['460', 'Inbound', 'Allow', 'Tcp', 'CycleCloud', 'subnet', 'compute', 'subnet', 'cyclecloud']

    // Deny all remaining traffic
    DenyVnetInbound: ['3100', 'Inbound', 'Deny', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    //
    // OUTBOUND RULES
    //    
    // Allow ssh from cyclecloud to compute
    AllowSshCyclecloudComputeOut: ['200', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'subnet', 'cyclecloud', 'subnet', 'compute']

    // CycleCloud
    AllowCycleClientComputeOut: ['320', 'Outbound', 'Allow', 'Tcp', 'CycleCloud', 'subnet', 'compute', 'subnet', 'cyclecloud']

    // All communications inside compute subnet
    AllowAllComputeComputeOut: ['540', 'Outbound', 'Allow', 'Tcp', 'All', 'subnet', 'compute', 'subnet', 'compute']

    // Deny all remaining traffic and allow Internet access
    AllowInternetOutBound: ['3000', 'Outbound', 'Allow', 'Tcp', 'All', 'tag', 'VirtualNetwork', 'tag', 'Internet']
    DenyVnetOutbound: ['3100', 'Outbound', 'Deny', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
  }
  // TODO: This rule is not applied, it should be removed
//  internet: {
//    AllowInternetHttpIn: ['210', 'Inbound', 'Allow', 'Tcp', 'Web', 'tag', 'Internet', 'subnet', 'frontend']
//  }
  // TODO: This rule is not applied, it should be removed
//  hub: {
//    AllowHubSshIn: ['200', 'Inbound', 'Allow', 'Tcp', 'HubSsh', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
//    AllowHubHttpIn: ['210', 'Inbound', 'Allow', 'Tcp', 'Web', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
//  }
  // TODO : Need to be validated
  mysql: {
    // Inbound
    AllowMySQLIn: ['700', 'Inbound', 'Allow', 'Tcp', 'MySQL', 'subnet', 'compute', 'subnet', 'database']
    // Outbound
    AllowMySQLOut: ['700', 'Outbound', 'Allow', 'Tcp', 'MySQL', 'subnet', 'compute', 'subnet', 'database']
  }
  // TODO : Need to be validated
  anf: {
    // Inbound
    AllowNfsComputeIn: ['435', 'Inbound', 'Allow', '*', 'Nfs', 'subnet', 'compute', 'subnet', 'netapp']
    // Outbound
    AllowNfsComputeOut: ['450', 'Outbound', 'Allow', '*', 'Nfs', 'subnet', 'compute', 'subnet', 'netapp']
  }
  // TODO : Need to be validated
  lustre: {
    // Inbound
    AllowLustreClientComputeIn: ['420', 'Inbound', 'Allow', 'Tcp', 'Lustre', 'subnet', 'compute', 'subnet', 'lustre']
    AllowLustreSubnetAnyInbound: ['430', 'Inbound', 'Allow', '*', 'All', 'subnet', 'lustre', 'subnet', 'lustre']
    // Outbound
    AllowAzureCloudServiceAccess: ['400', 'Outbound', 'Allow', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'AzureCloud']
    AllowLustreClientComputeOut: ['420', 'Outbound', 'Allow', 'Tcp', 'Lustre', 'subnet', 'compute', 'subnet', 'lustre']
    AllowLustreSubnetAnyOutbound: ['430', 'Outbound', 'Allow', '*', 'All', 'subnet', 'lustre', 'subnet', 'lustre']
  }
  // See documentation in https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg if we need to apply NSGs on the BastionSubnet
  bastion: {
    // This rule is to allow connectivity from Bastion to any VMs in the VNet
    AllowBastionIn: ['530', 'Inbound', 'Allow', 'Tcp', 'Bastion', 'subnet', 'bastion', 'tag', 'VirtualNetwork']
  }
}

var nsgRules = items(union(
  nsg_rules.default,
  deploy_bastion ? nsg_rules.bastion : {},
  create_anf ? nsg_rules.anf : {},
  create_lustre ? nsg_rules.lustre : {},
  create_database ? nsg_rules.mysql : {}))
var incomingSSHPort = 22 //todo FIX LATER
var servicePorts = {
  All: ['0-65535']
  Bastion: (incomingSSHPort == 22) ? ['22'] : ['22', string(incomingSSHPort)]
  Https: ['443']
  Web: ['443', '80']
  Ssh: ['22']
  HubSsh: [string(incomingSSHPort)]
  Dns: ['53']
  Lustre: ['988', '1019-1023']
  // 111: portmapper, 635: mountd, 2049: nfsd, 4045: nlockmgr, 4046: status, 4049: rquotad
  Nfs: ['111', '635', '2049', '4045', '4046', '4049']
  // HTTPS, AMQP
  CycleCloud: ['9443', '5672']
  MySQL: ['3306', '33060']
}
var securityRules = [ for rule in nsgRules : {
  name: rule.key
  properties: union(
    {
      priority: rule.value[0]
      direction: rule.value[1]
      access: rule.value[2]
      protocol: rule.value[3]
      sourcePortRange: '*'
      destinationPortRanges: servicePorts[rule.value[4]]
    },
    rule.value[5] == 'asg' ? { 
      sourceApplicationSecurityGroups: [{
        id: resourceId('Microsoft.Network/applicationSecurityGroups', rule.value[6])
      }] 
    } : {},
    rule.value[5] == 'tag' ? { sourceAddressPrefix: rule.value[6] } : {},
    rule.value[5] == 'subnet' ? { sourceAddressPrefix: vnet.subnets[rule.value[6]].cidr } : {},
    rule.value[5] == 'ips' ? { sourceAddressPrefixes: rule.value[6] } : {},

    rule.value[7] == 'asg' ? { 
      destinationApplicationSecurityGroups: [{
        id: resourceId('Microsoft.Network/applicationSecurityGroups', rule.value[8])
      }] 
    } : {},
    rule.value[7] == 'tag' ? { destinationAddressPrefix: rule.value[8] } : {},
    rule.value[7] == 'subnet' ? { destinationAddressPrefix: vnet.subnets[rule.value[8]].cidr } : {},
    rule.value[7] == 'ips' ? { destinationAddressPrefixes: rule.value[8] } : {}
  )
}]
//var asgNames = []

var peering_enabled = ccswConfig.network.vnet.peering.enabled
var peered_vnet_name = contains(ccswConfig.network.vnet.peering.vnet,'name') ? ccswConfig.network.vnet.peering.vnet.name : 'foo'
var peered_vnet_resource_group = contains(ccswConfig.network.vnet.peering.vnet,'id') ? split(ccswConfig.network.vnet.peering.vnet.id,'/')[4] : 'foo'
var peered_vnet_id = contains(ccswConfig.network.vnet.peering.vnet,'id') ? ccswConfig.network.vnet.peering.vnet.id : 'foo'

// resource asgs 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = [ for name in asgNames: {
//   name: name
//   location: location
//   tags: nsgTags
// }]

//output asgIds array = [ for i in range(0, length(asgNames)): { '${asgs[i].name}': asgs[i].id } ]

resource ccswCommonNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'nsg-ccsw-common'
  location: location
  tags: nsgTags
  properties: {
    securityRules: securityRules
  }
  // dependsOn: [
  //   asgs
  // ]
}

resource ccswVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnet.name
  location: location
  tags: contains(vnet, 'tags') ? vnet.tags : tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnet.cidr ]
    }
    subnets: [ for subnet in items(vnet.subnets): {
      name: subnet.value.name
      properties: {
        addressPrefix: subnet.value.cidr
        natGateway: (natGatewayId != '' && subnet.value.nat_gateway) ? {
          id: natGatewayId
        } : null
        networkSecurityGroup: subnet.value.name == 'AzureBastionSubnet' ? null : {
          id: ccswCommonNsg.id
        }
        delegations: map(subnet.value.delegations, delegation => {
          name: subnet.value.name
          properties: {
            serviceName: delegation
          }
        })
        serviceEndpoints: map(subnet.value.service_endpoints, endpoint => {
          service: endpoint
        }) 
      }
    }]
  }
}

resource ccsw_to_peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-07-01' = if (peering_enabled) {
  name: '${ccswVirtualNetwork.name}-to-${peered_vnet_name}-${uniqueString(resourceGroup().id)}'
  parent: ccswVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    useRemoteGateways: ccswConfig.network.vnet.peering.?allowGatewayTransit
    remoteVirtualNetwork: {
      id: peered_vnet_id
    }
  }
}

//module necessary due to change in scope
module peer_to_ccsw './network-peering.bicep' = if (peering_enabled) {
  name: 'peer_to_ccsw'
  scope: resourceGroup(peered_vnet_resource_group)
  params: {
    name: '${peered_vnet_name}-to-${ccswVirtualNetwork.name}-${uniqueString(resourceGroup().id)}'
    vnetName: peered_vnet_name
    vnetId: ccswVirtualNetwork.id
  }
}

//generate outputs for ccsw.bicep
func fetch_rsc_id(subId string, rg string, rscId string) string =>
  '/subscriptions/${subId}/resourceGroups/${rg}/providers/${rscId}'
func fetch_rsc_name(rscId string) string => last(split(rscId, '/'))
func rsc_output(rsc object) object => {
  id: fetch_rsc_id(rsc.subscriptionId, rsc.resourceGroupName, rsc.resourceId)
  name: fetch_rsc_name(rsc.resourceId)
  rg: rsc.resourceGroupName
  rsc_info: rsc
}

resource subnetCycleCloud 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = {
  name: vnet.subnets.cyclecloud.name
  parent: ccswVirtualNetwork
}
var subnet_cyclecloud = rsc_output(subnetCycleCloud)

resource subnetScheduler 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = if (deploy_scheduler) {
  name: contains(vnet.subnets,'scheduler') ? vnet.subnets.scheduler.name : 'foo'
  parent: ccswVirtualNetwork
}
var subnet_scheduler = deploy_scheduler ? rsc_output(subnetScheduler) : {}

resource subnetCompute 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = {
  name: vnet.subnets.compute.name
  parent: ccswVirtualNetwork
}
var subnet_compute = rsc_output(subnetCompute)

resource subnetNetApp 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = if (create_anf) {
  name: contains(vnet.subnets,'netapp') ? vnet.subnets.netapp.name : 'foo'
  parent: ccswVirtualNetwork
}
var subnet_netapp = create_anf ? rsc_output(subnetNetApp) : {}

resource subnetLustre 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = if (create_lustre) {
  name: contains(vnet.subnets,'lustre') ? vnet.subnets.lustre.name : 'foo'
  parent: ccswVirtualNetwork
}
var subnet_lustre = lustre_count > 0 ? rsc_output(subnetLustre) : {}

resource subnetBastion 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = if (deploy_bastion) {
  name: contains(vnet.subnets,'bastion') ? vnet.subnets.bastion.name : 'foo'
  parent: ccswVirtualNetwork
}
var subnet_bastion = deploy_bastion ? rsc_output(subnetBastion) : {}

resource subnetDatabase 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = if (create_database) {
  name: contains(vnet.subnets,'database') ? vnet.subnets.database.name : 'foo'
  parent: ccswVirtualNetwork
}
var subnet_database = create_database ? rsc_output(subnetDatabase) : {}

var filerTypeHome = ccswConfig.filesystem.shared.config.filertype
var filerTypeAddl = contains(ccswConfig.filesystem.?additional.?config ?? {}, 'filertype') ? ccswConfig.filesystem.additional.config.filertype : 'none'
var output_home_subnet = filerTypeHome == 'aml' || filerTypeHome == 'anf'
var output_addl_subnet = filerTypeAddl == 'aml' || filerTypeAddl == 'anf'
var home_filer = output_home_subnet ? (filerTypeHome == 'anf' ? { home: subnet_netapp } : { home: subnet_lustre }) : {}
var addl_filer = output_addl_subnet ? (filerTypeAddl == 'anf' ? { additional: subnet_netapp } : { additional: subnet_lustre }) : {}
var subnets = union(
  { cyclecloud: subnet_cyclecloud },
  { compute: subnet_compute },
  home_filer,
  addl_filer,
  deploy_scheduler ? { scheduler: subnet_scheduler } : {},
  deploy_bastion ? { bastion: subnet_bastion } : {},
  create_database ? { database: subnet_database } : {}
)

output nsg_ccsw object = rsc_output(ccswCommonNsg)
output vnet_ccsw object = rsc_output(ccswVirtualNetwork)
output subnets_ccsw object = subnets
