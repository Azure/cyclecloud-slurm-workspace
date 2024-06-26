targetScope = 'resourceGroup'

param name string
param vm object
param image object
param location string
param tags object
param networkInterfacesTags object
//param resourcePostfix string = '${uniqueString(subscription().subscriptionId, resourceGroup().id)}x'
param subnetId string
param adminUser string
// @secure()
// param adminPassword string
@secure()
param adminSshPublicKey string
//param asgIds object

resource nic 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: '${name}-nic'
  location: location
  tags: networkInterfacesTags
  properties: {
    ipConfigurations: [
      {
        name: '${name}-ipconfig'
        properties: {
//            applicationSecurityGroups: map(vm.asgs, asg => { id: asgIds[asg] })
            subnet: {
              id: subnetId
            }
            privateIPAllocationMethod: 'Dynamic'
          }
      }
    ]
  }
}

var datadisks = contains(vm, 'datadisks') ? vm.datadisks : []

resource virtualMachine 'Microsoft.Compute/virtualMachines@2022-11-01' = {
  name: '${name}-vm'
  location: location
  tags: tags
  plan: contains(image, 'plan') && empty(image.plan) == false ? {
    publisher: split(image.plan,':')[0]
    product: split(image.plan,':')[1]
    name: split(image.plan,':')[2]
  } : null
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vm.sku
    }
    storageProfile: {
      dataDisks: [ for (disk, idx) in datadisks: union({
        name: disk.name
        managedDisk: {
          storageAccountType: disk.disksku
        }
        lun: idx
        createOption: disk.createOption
        },
        disk.createOption == 'FromImage' ? {} : {diskSizeGB: disk.size},
        contains(disk, 'caching') ? {
          caching: disk.caching
        } : {}
      )]
      osDisk: union(
        {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: vm.osdisksku
          }
          caching: 'ReadWrite'
        }, contains(vm, 'osdisksize') ? {
          diskSizeGB: vm.osdisksize
        } : {}
      )
      imageReference: image.ref
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    osProfile: union(
      {
        computerName: name
        adminUsername: adminUser
      }, 
      contains(vm, 'deploy_script') && vm.deploy_script != '' ? { // deploy script not empty
        customData: base64(vm.deploy_script)
      } : {}, 
      !contains(vm, 'windows') || vm.windows == false ? { // linux
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUser}/.ssh/authorized_keys'
                keyData: adminSshPublicKey
              }
            ]
          }
        }
      } : {}, contains(vm, 'ahub') && vm.ahub == true ? { // ahub
        licenseType: 'Windows_Server'
      } : {}
    )
  }
}
output fqdn string = '' //contains(vm, 'pip') && vm.pip ? publicIp.properties.dnsSettings.fqdn : ''
output publicIp string = '' //contains(vm, 'pip') && vm.pip ? publicIp.properties.ipAddress : ''
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output principalId string = virtualMachine.identity.principalId
//output privateIps array = [ for i in range(0, count): nic[i].properties.ipConfigurations[0].properties.privateIPAddress ]
//output principalIds array = [ for i in range(0, count): virtualMachine[i].identity.principalId ]
