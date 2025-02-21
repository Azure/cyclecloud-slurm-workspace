import * as types from './types.bicep'

param network types.vnet_t
param address string = network.?addressSpace
param location string
param tags types.tags_t
param nsgTags types.tags_t
param sharedFilesystem types.sharedFilesystem_t
param additionalFilesystem types.additionalFilesystem_t 
var filerTypes = [sharedFilesystem.type, additionalFilesystem.type]
var create_anf = contains(filerTypes, 'anf-new')
var create_anf_subnet = create_anf ? (sharedFilesystem.type == 'anf-new' ? network.?sharedFilerSubnet : network.?additionalFilerSubnet) : null
var create_lustre = additionalFilesystem.type == 'aml-new'
var deploy_bastion = network.?bastion ?? false
var create_database = false //update once MySQL capacity is available
param natGatewayId string 
param databaseConfig types.databaseConfig_t
var create_private_endpoint = databaseConfig.type == 'privateEndpoint'

//purpose: calculate 2^n for n between 0 and 3 or return 0 if n is -1, otherwise -1
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

func subnet_config(ip string) object => subnet_ranges(decompose_ip(ip),subnet_octets(get_cidr(ip)))

var subnet_cidr = subnet_config(address)

var vnet  = {
  name: network.?name ?? 'ccw-vnet'
  cidr: address
  subnets: union(
    {
      cyclecloud: {
        name: network.?cyclecloudSubnet ?? 'ccw-cyclecloud-subnet'
        cidr: subnet_cidr.cyclecloud
        nat_gateway: true
        service_endpoints: []
        delegations: []
      }
      compute: {
        name: network.?computeSubnet ?? 'ccw-compute-subnet'
        cidr: subnet_cidr.compute
        nat_gateway : true 
        service_endpoints: []
        delegations: []
      }
    },
    create_anf ? {
      netapp: {
        name: create_anf_subnet ?? 'ccw-anf-subnet'
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
        name: network.?additionalFilerSubnet ?? 'ccw-lustre-subnet'
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
        nat_gateway : true
        service_endpoints: []
        delegations: []
      }
    } : {},
    create_database ? {
      database: {
        name: 'ccw-database-subnet'
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

    // Allow ssh from VirtualNetwork to VirtualNetwork to allow SSH from peered or VPN connected VNets
    AllowSshVnetVnetIn: ['250', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    // All communications inside compute subnet
    AllowAllComputeComputeIn: ['365', 'Inbound', 'Allow', 'Tcp', 'All', 'subnet', 'compute', 'subnet', 'compute']

    // CycleCloud
    AllowCycleClientComputeIn: ['460', 'Inbound', 'Allow', 'Tcp', 'CycleCloud', 'subnet', 'compute', 'subnet', 'cyclecloud']

    // Deny all remaining traffic
    DenyVnetInbound: ['3100', 'Inbound', 'Deny', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    //
    // OUTBOUND RULES
    //    
    // Allow https outgoing connections
    AllowHttpsOut: ['100', 'Outbound', 'Allow', 'Tcp', 'Https', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
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
    // Inbound
    AllowHttps_bastion_In: ['500', 'Inbound', 'Allow', 'Tcp', 'Https', 'tag', 'Internet', 'subnet', 'bastion']
    AllowGatewayManager_bastion_In: ['502', 'Inbound', 'Allow', 'Tcp', 'Https', 'tag', 'GatewayManager', 'tag', '*']
    AllowAzureLoadBalancer_bastion_In: ['504', 'Inbound', 'Allow', 'Tcp', 'Https', 'tag', 'AzureLoadBalancer', 'tag', '*']
    AllowBastionHostCommunication_bastion_In: ['506', 'Inbound', 'Allow', 'Tcp', 'Bastion', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
    // This rule is to allow connectivity from Bastion to any VMs in the VNet
    AllowSsh_bastion_In: ['530', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'subnet', 'bastion', 'tag', 'VirtualNetwork']
    // Outbound
    AllowSshRdp_bastion_Out: ['500', 'Outbound', 'Allow', 'Tcp', 'SshRdp', 'tag', '*', 'tag', 'VirtualNetwork']
    AllowAzureCloud_bastion_Out: ['502', 'Outbound', 'Allow', 'Tcp', 'Https', 'tag', '*', 'tag', 'AzureCloud']
    AllowBastionHostCommunication_bastion_Out: ['504', 'Outbound', 'Allow', 'Tcp', 'Bastion', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
    AllowHttp_bastion_Out: ['506', 'Outbound', 'Allow', 'Tcp', 'Http', 'tag', '*', 'tag', 'Internet']
    AllowHttps_bastion_Out: ['508', 'Outbound', 'Allow', 'Tcp', 'Https', 'subnet', 'bastion', 'tag', 'VirtualNetwork']    
  }
}

var nsgRules = items(union(
  nsg_rules.default,
  deploy_bastion ? nsg_rules.bastion : {},
  create_anf ? nsg_rules.anf : {},
  create_lustre ? nsg_rules.lustre : {},
  create_database ? nsg_rules.mysql : {}))
var servicePorts = {
  All: ['0-65535']
  Bastion: ['8080','5701']
  Https: ['443']
  Http: ['80']
  Ssh: ['22']
  Lustre: ['988', '1019-1023']
  // 111: portmapper, 635: mountd, 2049: nfsd, 4045: nlockmgr, 4046: status, 4049: rquotad
  Nfs: ['111', '635', '2049', '4045', '4046', '4049']
  // HTTPS, AMQP
  CycleCloud: ['9443', '5672']
  MySQL: ['3306', '33060']
  SshRdp: ['22', '3389']
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

var peeringEnabled = contains(network,'vnetToPeer')
var peeredVnetName = peeringEnabled ? network.?vnetToPeer.name : 'foo'
var peeredVnetResourceGroup = peeringEnabled ? split(network.?vnetToPeer.id,'/')[4] : 'foo'
var peeredVnetId = peeringEnabled ? network.?vnetToPeer.id : 'foo'

resource ccwCommonNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-ccw-common'
  location: location
  tags: nsgTags
  properties: {
    securityRules: securityRules
  }
}

resource ccwVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnet.name
  location: location
  tags: tags
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
        networkSecurityGroup: {
          id: ccwCommonNsg.id
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

resource ccw_to_peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = if (peeringEnabled) {
  name: '${ccwVirtualNetwork.name}-to-${peeredVnetName}-${uniqueString(resourceGroup().id)}'
  parent: ccwVirtualNetwork
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    useRemoteGateways: network.?peeringAllowGatewayTransit
    remoteVirtualNetwork: {
      id: peeredVnetId
    }
  }
}

//module necessary due to change in scope
module peer_to_ccw './network-peering.bicep' = if (peeringEnabled) {
  name: 'peer_to_ccw'
  scope: resourceGroup(peeredVnetResourceGroup)
  params: {
    name: '${peeredVnetName}-to-${ccwVirtualNetwork.name}-${uniqueString(resourceGroup().id)}'
    vnetName: peeredVnetName
    vnetId: ccwVirtualNetwork.id
  }
}

//generate outputs for ccw.bicep
func fetch_rsc_id(subId string, rg string, rscId string) string =>
  '/subscriptions/${subId}/resourceGroups/${rg}/providers/${rscId}'
func fetch_rsc_name(rscId string) string => last(split(rscId, '/'))
func rsc_output(rsc object) types.rsc_t => {
  id: fetch_rsc_id(rsc.subscriptionId, rsc.resourceGroupName, rsc.resourceId)
  name: fetch_rsc_name(rsc.resourceId)
  rg: rsc.resourceGroupName
}

resource subnetCycleCloud 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: vnet.subnets.cyclecloud.name
  parent: ccwVirtualNetwork
}
var subnet_cyclecloud = rsc_output(subnetCycleCloud)

resource subnetCompute 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  name: vnet.subnets.compute.name
  parent: ccwVirtualNetwork
}
var subnet_compute = rsc_output(subnetCompute)

resource subnetNetApp 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = if (create_anf) {
  name: contains(vnet.subnets,'netapp') ? vnet.subnets.netapp.name : 'foo'
  parent: ccwVirtualNetwork
}
var subnet_netapp = create_anf ? rsc_output(subnetNetApp) : {}

resource subnetLustre 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = if (create_lustre) {
  name: contains(vnet.subnets,'lustre') ? vnet.subnets.lustre.name : 'foo'
  parent: ccwVirtualNetwork
}
//var subnet_lustre = lustre_count > 0 ? rsc_output(subnetLustre) : {}
var subnet_lustre = create_lustre ? rsc_output(subnetLustre) : {}

resource subnetBastion 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = if (deploy_bastion) {
  name: contains(vnet.subnets,'bastion') ? vnet.subnets.bastion.name : 'foo'
  parent: ccwVirtualNetwork
}
var subnet_bastion = deploy_bastion ? rsc_output(subnetBastion) : {}

resource subnetDatabase 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = if (create_database) {
  name: contains(vnet.subnets,'database') ? vnet.subnets.database.name : 'foo'
  parent: ccwVirtualNetwork
}
var subnet_database = create_database ? rsc_output(subnetDatabase) : {}

var filerTypeHome = sharedFilesystem.type
var filerTypeAddl = additionalFilesystem.type
var output_home_subnet = filerTypeHome == 'anf-new' 
var output_addl_subnet = contains(['aml-new','anf-new'],filerTypeAddl)
var home_filer = output_home_subnet ? (filerTypeHome == 'anf-new' ? { home: subnet_netapp } : { home: subnet_lustre }) : {}
var addl_filer = output_addl_subnet ? (filerTypeAddl == 'anf-new' ? { additional: subnet_netapp } : { additional: subnet_lustre }) : {}
var subnets = union(
  { cyclecloud: subnet_cyclecloud },
  { compute: subnet_compute },
  home_filer,
  addl_filer,
  deploy_bastion ? { bastion: subnet_bastion } : {},
  create_database ? { database: subnet_database } : {}
)

resource ccwDatabase 'Microsoft.DBforMySQL/flexibleServers@2023-10-01-preview' existing = if (create_private_endpoint && databaseConfig.type != 'disabled') {
  name: databaseConfig.?dbInfo.?name ?? 'disabled'
  scope: resourceGroup(split(databaseConfig.?dbInfo.?id ?? '////','/')[4])
}

var privateEndpointName = 'ccw-mysql-pe'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = if (create_private_endpoint) {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: subnetCompute.id
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: ccwDatabase.id
          groupIds: ['mysqlServer']
        }
      }
    ]
  }
}

output nsgCCW types.rsc_t = rsc_output(ccwCommonNsg)
output vnetCCW types.rsc_t = rsc_output(ccwVirtualNetwork)
output subnetsCCW types.subnets_t = subnets
output databaseFQDN string = create_private_endpoint ? privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0] : ''
