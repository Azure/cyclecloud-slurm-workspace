param address string = ccswConfig.network.vnet.address_space
param location string
param ccswConfig object

param create_anf bool = ccswConfig.filesystem.shared.config.filertype == 'anf' || (contains(ccswConfig.filesystem.additional.config,'filertype') && ccswConfig.filesystem.additional.config.filertype == 'anf')
param lustre_count int = (ccswConfig.filesystem.shared.config.filertype == 'aml' ? 1 : 0) + ((contains(ccswConfig.filesystem.additional.config,'filertype') && ccswConfig.filesystem.additional.config.filertype == 'aml') ? 1 : 0)
param create_lustre bool = lustre_count > 0
param deploy_bastion bool = ccswConfig.network.vnet.bastion
param create_database bool = ccswConfig.slurm_settings.scheduler_node.slurmAccounting
param deploy_scheduler bool

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
  cyclecloud: { //frontend
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
        service_endpoints: [
          'Microsoft.Storage'
        ]
        delegations: []
      }
      compute: {
        name: ccswConfig.network.vnet.subnets.computeSubnet
        cidr: subnet_cidr.compute
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
        service_endpoints: []
        delegations: []
      }
    } : {},
    deploy_bastion ? {
      bastion: {
        name: 'AzureBastionSubnet'
        cidr: subnet_cidr.bastion
        service_endpoints: []
        delegations: []
      }
    } : {},
    create_database ? {
      database: {
        name: 'hpc-database-subnet'
        cidr: subnet_cidr.database
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

    // SSH internal rules
    AllowSshFromJumpboxIn: ['320', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-jumpbox', 'asg', 'asg-ssh']
    AllowSshFromComputeIn: ['330', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'subnet', 'compute', 'asg', 'asg-ssh']
    AllowSshToComputeIn: ['360', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-ssh', 'subnet', 'compute']

    // All communications inside compute subnet
    AllowAllComputeComputeIn: ['365', 'Inbound', 'Allow', 'Tcp', 'All', 'subnet', 'compute', 'subnet', 'compute']

    // Scheduler
    AllowSchedIn: ['369', 'Inbound', 'Allow', '*', 'Shed', 'asg', 'asg-sched', 'asg', 'asg-sched']
    //AllowPbsClientIn            : ['370', 'Inbound', 'Allow', '*', 'Pbs', 'asg', 'asg-pbs-client', 'asg', 'asg-pbs']
    AllowSchedComputeIn: ['380', 'Inbound', 'Allow', '*', 'Shed', 'asg', 'asg-sched', 'subnet', 'compute']
    //      AllowComputePbsClientIn     : ['390', 'Inbound', 'Allow', '*', 'Pbs', 'subnet', 'compute', 'asg', 'asg-pbs-client']
    AllowComputeSchedIn: ['400', 'Inbound', 'Allow', '*', 'Shed', 'subnet', 'compute', 'asg', 'asg-sched']
    //      AllowComputeComputeSchedIn  : ['401', 'Inbound', 'Allow', '*', 'Shed', 'subnet', 'compute', 'subnet', 'compute']

    // CycleCloud
    AllowCycleClientIn: [
      '450'
      'Inbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'asg'
      'asg-cyclecloud-client'
      'asg'
      'asg-cyclecloud'
    ]
    AllowCycleClientComputeIn: [
      '460'
      'Inbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'subnet'
      'compute'
      'asg'
      'asg-cyclecloud'
    ]
    AllowCycleServerIn: [
      '465'
      'Inbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'asg'
      'asg-cyclecloud'
      'asg'
      'asg-cyclecloud-client'
    ]

    // Deny all remaining traffic
    DenyVnetInbound: ['3100', 'Inbound', 'Deny', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    //
    // Outbound
    //

    // CycleCloud
    AllowCycleServerOut: [
      '300'
      'Outbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'asg'
      'asg-cyclecloud'
      'asg'
      'asg-cyclecloud-client'
    ]
    AllowCycleClientOut: [
      '310'
      'Outbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'asg'
      'asg-cyclecloud-client'
      'asg'
      'asg-cyclecloud'
    ]
    AllowComputeCycleClientIn: [
      '320'
      'Outbound'
      'Allow'
      'Tcp'
      'CycleCloud'
      'subnet'
      'compute'
      'asg'
      'asg-cyclecloud'
    ]

    // Scheduler
    AllowSchedOut: ['340', 'Outbound', 'Allow', '*', 'Shed', 'asg', 'asg-sched', 'asg', 'asg-sched']
    //      AllowPbsClientOut           : ['350', 'Outbound', 'Allow', '*', 'Pbs', 'asg', 'asg-pbs-client', 'asg', 'asg-pbs']
    AllowSchedComputeOut: ['360', 'Outbound', 'Allow', '*', 'Shed', 'asg', 'asg-sched', 'subnet', 'compute']
    AllowComputeSchedOut: ['370', 'Outbound', 'Allow', '*', 'Shed', 'subnet', 'compute', 'asg', 'asg-sched']
    //AllowComputePbsClientOut    : ['380', 'Outbound', 'Allow', '*', 'Pbs', 'subnet', 'compute', 'asg', 'asg-pbs-client']
    //      AllowComputeComputeSchedOut : ['381', 'Outbound', 'Allow', '*', 'Shed', 'subnet', 'compute', 'subnet', 'compute']

    // SSH internal rules
    AllowSshFromJumpboxOut: ['490', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-jumpbox', 'asg', 'asg-ssh']
    AllowSshComputeOut: ['500', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-ssh', 'subnet', 'compute']
    AllowSshFromComputeOut: ['530', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'subnet', 'compute', 'asg', 'asg-ssh']

    // All communications inside compute subnet
    AllowAllComputeComputeOut: ['540', 'Outbound', 'Allow', 'Tcp', 'All', 'subnet', 'compute', 'subnet', 'compute']

    // Admin and Deployment
    AllowDnsOut: ['590', 'Outbound', 'Allow', '*', 'Dns', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']

    // Deny all remaining traffic and allow Internet access
    AllowInternetOutBound: ['3000', 'Outbound', 'Allow', 'Tcp', 'All', 'tag', 'VirtualNetwork', 'tag', 'Internet']
    DenyVnetOutbound: ['3100', 'Outbound', 'Deny', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
  }
  internet: {
    AllowInternetSshIn: ['200', 'Inbound', 'Allow', 'Tcp', 'HubSsh', 'tag', 'Internet', 'asg', 'asg-jumpbox']
    AllowInternetHttpIn: ['210', 'Inbound', 'Allow', 'Tcp', 'Web', 'tag', 'Internet', 'subnet', 'frontend']
  }
  hub: {
    AllowHubSshIn: ['200', 'Inbound', 'Allow', 'Tcp', 'HubSsh', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
    AllowHubHttpIn: ['210', 'Inbound', 'Allow', 'Tcp', 'Web', 'tag', 'VirtualNetwork', 'tag', 'VirtualNetwork']
  }
  /*ad: {
    // Inbound
    // AD communication
    AllowAdServerTcpIn: [
      '220'
      'Inbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'asg'
      'asg-ad-client'
    ]
    AllowAdServerUdpIn: [
      '230'
      'Inbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'asg'
      'asg-ad-client'
    ]
    AllowAdClientTcpIn: [
      '240'
      'Inbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      'asg'
      'asg-ad-client'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdClientUdpIn: [
      '250'
      'Inbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      'asg'
      'asg-ad-client'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdServerComputeTcpIn: [
      '260'
      'Inbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'subnet'
      'compute'
    ]
    AllowAdServerComputeUdpIn: [
      '270'
      'Inbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'subnet'
      'compute'
    ]
    AllowAdClientComputeTcpIn: [
      '280'
      'Inbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      'subnet'
      'compute'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdClientComputeUdpIn: [
      '290'
      'Inbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      'subnet'
      'compute'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowWinRMIn: ['520', 'Inbound', 'Allow', 'Tcp', 'WinRM', 'asg', 'asg-jumpbox', 'asg', 'asg-rdp']
    AllowRdpIn: ['550', 'Inbound', 'Allow', 'Tcp', 'Rdp', 'asg', 'asg-jumpbox', 'asg', 'asg-rdp']
    // Outbound
    // AD communication
    AllowAdClientTcpOut: [
      '200'
      'Outbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      'asg'
      'asg-ad-client'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdClientUdpOut: [
      '210'
      'Outbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      'asg'
      'asg-ad-client'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdClientComputeTcpOut: [
      '220'
      'Outbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      'subnet'
      'compute'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdClientComputeUdpOut: [
      '230'
      'Outbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      'subnet'
      'compute'
      nsgTargetForDC.type
      nsgTargetForDC.target
    ]
    AllowAdServerTcpOut: [
      '240'
      'Outbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'asg'
      'asg-ad-client'
    ]
    AllowAdServerUdpOut: [
      '250'
      'Outbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'asg'
      'asg-ad-client'
    ]
    AllowAdServerComputeTcpOut: [
      '260'
      'Outbound'
      'Allow'
      'Tcp'
      'DomainControlerTcp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'subnet'
      'compute'
    ]
    AllowAdServerComputeUdpOut: [
      '270'
      'Outbound'
      'Allow'
      'Udp'
      'DomainControlerUdp'
      nsgTargetForDC.type
      nsgTargetForDC.target
      'subnet'
      'compute'
    ]
    AllowRdpOut: ['570', 'Outbound', 'Allow', 'Tcp', 'Rdp', 'asg', 'asg-jumpbox', 'asg', 'asg-rdp']
    AllowWinRMOut: ['580', 'Outbound', 'Allow', 'Tcp', 'WinRM', 'asg', 'asg-jumpbox', 'asg', 'asg-rdp']
  }*/
  ondemand: {
    // Inbound
    //AllowComputeSlurmIn         : ['405', 'Inbound', 'Allow', '*', 'Slurmd', 'asg', 'asg-ondemand', 'subnet', 'compute']
    AllowCycleWebIn: ['440', 'Inbound', 'Allow', 'Tcp', 'Web', 'asg', 'asg-ondemand', 'asg', 'asg-cyclecloud']
    AllowComputeNoVncIn: ['470', 'Inbound', 'Allow', 'Tcp', 'NoVnc', 'subnet', 'compute', 'asg', 'asg-ondemand']
    AllowNoVncComputeIn: ['480', 'Inbound', 'Allow', 'Tcp', 'NoVnc', 'asg', 'asg-ondemand', 'subnet', 'compute']
    // Not sure if this is really needed. Why opening web port from deployer to ondemand ?
    // AllowWebDeployerIn          : ['595', 'Inbound', 'Allow', 'Tcp', 'Web', 'asg', 'asg-deployer', 'asg', 'asg-ondemand']
    // Outbound
    AllowCycleWebOut: ['330', 'Outbound', 'Allow', 'Tcp', 'Web', 'asg', 'asg-ondemand', 'asg', 'asg-cyclecloud']
    //AllowSlurmComputeOut        : ['385', 'Outbound', 'Allow', '*', 'Slurmd', 'asg', 'asg-ondemand', 'subnet', 'compute']
    AllowComputeNoVncOut: ['550', 'Outbound', 'Allow', 'Tcp', 'NoVnc', 'subnet', 'compute', 'asg', 'asg-ondemand']
    AllowNoVncComputeOut: ['560', 'Outbound', 'Allow', 'Tcp', 'NoVnc', 'asg', 'asg-ondemand', 'subnet', 'compute']
    // AllowWebDeployerOut         : ['595', 'Outbound', 'Allow', 'Tcp', 'Web', 'asg', 'asg-deployer', 'asg', 'asg-ondemand']
  }
  mysql: {
    // Inbound
    AllowMySQLIn: ['700', 'Inbound', 'Allow', 'Tcp', 'MySQL', 'asg', 'asg-mysql-client', 'subnet', 'database']
    // Outbound
    AllowMySQLOut: ['700', 'Outbound', 'Allow', 'Tcp', 'MySQL', 'asg', 'asg-mysql-client', 'subnet', 'database']
  }
  anf: {
    // Inbound
    AllowNfsIn: ['434', 'Inbound', 'Allow', '*', 'Nfs', 'asg', 'asg-nfs-client', 'subnet', 'netapp']
    AllowNfsComputeIn: ['435', 'Inbound', 'Allow', '*', 'Nfs', 'subnet', 'compute', 'subnet', 'netapp']
    // Outbound
    AllowNfsOut: ['440', 'Outbound', 'Allow', '*', 'Nfs', 'asg', 'asg-nfs-client', 'subnet', 'netapp']
    AllowNfsComputeOut: ['450', 'Outbound', 'Allow', '*', 'Nfs', 'subnet', 'compute', 'subnet', 'netapp']
  }
  /*ad_anf: {
  // Inbound
    AllowAdServerNetappTcpIn    : ['300', 'Inbound', 'Allow', 'Tcp', 'DomainControlerTcp', 'subnet', 'netapp', nsgTargetForDC.type, nsgTargetForDC.target]
    AllowAdServerNetappUdpIn    : ['310', 'Inbound', 'Allow', 'Udp', 'DomainControlerUdp', 'subnet', 'netapp', nsgTargetForDC.type, nsgTargetForDC.target]
    // Outbound
    AllowAdServerNetappTcpOut   : ['280', 'Outbound', 'Allow', 'Tcp', 'DomainControlerTcp', nsgTargetForDC.type, nsgTargetForDC.target, 'subnet', 'netapp']
    AllowAdServerNetappUdpOut   : ['290', 'Outbound', 'Allow', 'Udp', 'DomainControlerUdp', nsgTargetForDC.type, nsgTargetForDC.target, 'subnet', 'netapp']
  }*/
  lustre: {
    // Inbound
    AllowLustreClientIn: ['410', 'Inbound', 'Allow', 'Tcp', 'Lustre', 'asg', 'asg-lustre-client', 'subnet', 'lustre']
    AllowLustreClientComputeIn: ['420', 'Inbound', 'Allow', 'Tcp', 'Lustre', 'subnet', 'compute', 'subnet', 'lustre']
    AllowLustreSubnetAnyInbound: ['430', 'Inbound', 'Allow', '*', 'All', 'subnet', 'lustre', 'subnet', 'lustre']
    // Outbound
    AllowAzureCloudServiceAccess: ['400', 'Outbound', 'Allow', '*', 'All', 'tag', 'VirtualNetwork', 'tag', 'AzureCloud']
    AllowLustreClientOut: ['410', 'Outbound', 'Allow', 'Tcp', 'Lustre', 'asg', 'asg-lustre-client', 'subnet', 'lustre']
    AllowLustreClientComputeOut: ['420', 'Outbound', 'Allow', 'Tcp', 'Lustre', 'subnet', 'compute', 'subnet', 'lustre']
    AllowLustreSubnetAnyOutbound: ['430', 'Outbound', 'Allow', '*', 'All', 'subnet', 'lustre', 'subnet', 'lustre']
  }
  bastion: {
    AllowBastionIn: ['530', 'Inbound', 'Allow', 'Tcp', 'Bastion', 'subnet', 'bastion', 'tag', 'VirtualNetwork']
  }
  gateway: {
    AllowInternalWebUsersIn: ['540', 'Inbound', 'Allow', 'Tcp', 'Web', 'subnet', 'gateway', 'asg', 'asg-ondemand']
  }
  grafana: {
    // Telegraf / Grafana
    // Inbound
    AllowTelegrafIn: ['490', 'Inbound', 'Allow', 'Tcp', 'Telegraf', 'asg', 'asg-telegraf', 'asg', 'asg-grafana']
    AllowComputeTelegrafIn: ['500', 'Inbound', 'Allow', 'Tcp', 'Telegraf', 'subnet', 'compute', 'asg', 'asg-grafana']
    AllowGrafanaIn: ['510', 'Inbound', 'Allow', 'Tcp', 'Grafana', 'asg', 'asg-ondemand', 'asg', 'asg-grafana']
    // Outbound
    AllowTelegrafOut: ['460', 'Outbound', 'Allow', 'Tcp', 'Telegraf', 'asg', 'asg-telegraf', 'asg', 'asg-grafana']
    AllowComputeTelegrafOut: ['470', 'Outbound', 'Allow', 'Tcp', 'Telegraf', 'subnet', 'compute', 'asg', 'asg-grafana']
    AllowGrafanaOut: ['480', 'Outbound', 'Allow', 'Tcp', 'Grafana', 'asg', 'asg-ondemand', 'asg', 'asg-grafana']
  }
  deployer: {
    // Inbound
    AllowSshFromDeployerIn: ['340', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-deployer', 'asg', 'asg-ssh']
    AllowDeployerToPackerSshIn: ['350', 'Inbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-deployer', 'subnet', 'admin']
    // Outbound
    AllowSshDeployerOut: ['510', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-deployer', 'asg', 'asg-ssh']
    AllowSshDeployerPackerOut: ['520', 'Outbound', 'Allow', 'Tcp', 'Ssh', 'asg', 'asg-deployer', 'subnet', 'admin']
  }
}

var nsgRules = items(union(
  nsg_rules.default,
  deploy_bastion ? nsg_rules.bastion : {},
  //config.deploy_gateway ? config.nsg_rules.gateway : {},
  create_anf ? nsg_rules.anf : {},
  create_lustre ? nsg_rules.lustre : {},
  //config.deploy_grafana ? config.nsg_rules.grafana : {},
  //config.deploy_ondemand ? config.nsg_rules.ondemand : {},
  create_database ? nsg_rules.mysql : {}))
var incomingSSHPort = 22 //todo FIX LATER
var servicePorts = {
  All: ['0-65535']
  Bastion: (incomingSSHPort == 22) ? ['22', '3389'] : ['22', string(incomingSSHPort), '3389']
  Web: ['443', '80']
  Ssh: ['22']
  HubSsh: [string(incomingSSHPort)]
  // DNS, Kerberos, RpcMapper, Ldap, Smb, KerberosPass, LdapSsl, LdapGc, LdapGcSsl, AD Web Services, RpcSam
  DomainControlerTcp: ['53', '88', '135', '389', '445', '464', '636', '3268', '3269', '9389', '49152-65535']
  // DNS, Kerberos, W32Time, NetBIOS, Ldap, KerberosPass, LdapSsl
  DomainControlerUdp: ['53', '88', '123', '138', '389', '464', '636']
  // Web, NoVNC, WebSockify
  NoVnc: ['80', '443', '5900-5910', '61001-61010']
  Dns: ['53']
  Rdp: ['3389']
  //Pbs: ['6200', '15001-15009', '17001', '32768-61000']
  //Slurm: ['6817-6819']
  Shed: ['6817-6819', '59000-61000']
  Lustre: ['988', '1019-1023']
  Nfs: ['111', '635', '2049', '4045', '4046']
  SMB: ['445']
  Telegraf: ['8086']
  Grafana: ['3000']
  // HTTPS, AMQP
  CycleCloud: ['9443', '5672']
  MySQL: ['3306', '33060']
  WinRM: ['5985', '5986']
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
var asgNames = union([ 'asg-ssh', 'asg-jumpbox', 'asg-sched', 'asg-cyclecloud', 'asg-cyclecloud-client', 'asg-nfs-client','asg-deployer' ], create_lustre ? [ 'asg-lustre-client' ] : [], create_database ? ['asg-mysql-client'] : [])

var peering_enabled = ccswConfig.network.vnet.peering.enabled
var peered_vnet_name = contains(ccswConfig.network.vnet.peering.vnet,'name') ? ccswConfig.network.vnet.peering.vnet.name : 'foo'
var peered_vnet_resource_group = contains(ccswConfig.network.vnet.peering.vnet,'id') ? split(ccswConfig.network.vnet.peering.vnet.id,'/')[4] : 'foo'
var peered_vnet_id = contains(ccswConfig.network.vnet.peering.vnet,'id') ? ccswConfig.network.vnet.peering.vnet.id : 'foo'

resource asgs 'Microsoft.Network/applicationSecurityGroups@2022-07-01' = [ for name in asgNames: {
  name: name
  location: location
}]

output asgIds array = [ for i in range(0, length(asgNames)): { '${asgs[i].name}': asgs[i].id } ]

resource ccswCommonNsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: 'nsg-ccsw-common'
  location: location
  properties: {
    securityRules: securityRules
  }
  dependsOn: [
    asgs
  ]
}

resource ccswVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnet.name
  location: location
  tags: contains(vnet, 'tags') ? vnet.tags : {}
  properties: {
    addressSpace: {
      addressPrefixes: [ vnet.cidr ]
    }
    subnets: [ for subnet in items(vnet.subnets): {
      name: subnet.value.name
      properties: {
        addressPrefix: subnet.value.cidr
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
    useRemoteGateways: true 
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

var filerType1 = ccswConfig.filesystem.shared.config.filertype
var filerType2 = contains(ccswConfig.filesystem.additional.config, 'filertype') ? ccswConfig.filesystem.additional.config.filertype : 'none'
var need_filer1_subnet = filerType1 == 'aml' || filerType1 == 'anf'
var need_filer2_subnet = filerType2 == 'aml' || (filerType2 == 'anf' && filerType1 != 'anf')
var filer1 = need_filer1_subnet ? (filerType1 == 'anf' ? { anf: subnet_netapp } : { lustre: subnet_lustre }) : {}
var filer2 = need_filer2_subnet ? (filerType2 == 'anf' ? { anf: subnet_netapp } : { lustre: subnet_lustre }) : {}
var subnets = union(
  { cyclecloud: subnet_cyclecloud },
  { compute: subnet_compute },
  filer1,
  filer2,
  deploy_scheduler ? { scheduler: subnet_scheduler } : {},
  deploy_bastion ? { bastion: subnet_bastion } : {},
  create_database ? { database: subnet_database } : {}
)

output nsg_ccsw object = rsc_output(ccswCommonNsg)
output vnet_ccsw object = rsc_output(ccswVirtualNetwork)
output subnets_ccsw object = subnets
