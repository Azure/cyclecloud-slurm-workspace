targetScope = 'resourceGroup'
import {tags_t} from './types.bicep'

param name string
param deployScript string 
param osDiskSku string
//param vm object
param image object
param location string
param tags tags_t
param networkInterfacesTags object
//param resourcePostfix string = '${uniqueString(subscription().subscriptionId, resourceGroup().id)}x'
param subnetId string
param adminUser string
// @secure()
// param adminPassword string
@secure()
param adminSshPublicKey string
//param asgIds object
param vmSize string
param dataDisks array
param osDiskSize int = 0 //TODO: add to UI

resource nic 'Microsoft.Network/networkInterfaces@2023-06-01' = {
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
      vmSize: vmSize
    }
    storageProfile: {
      dataDisks: [ for (disk, idx) in dataDisks: union({
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
            storageAccountType: osDiskSku
          }
          caching: 'ReadWrite'
        }, osDiskSize > 0 ? {
          diskSizeGB: osDiskSize
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
      deployScript != '' ? { // deploy script not empty
        customData: base64(deployScript)
      } : {}, 
      { // linux
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
      }
    )
  }
}
output fqdn string = '' //contains(vm, 'pip') && vm.pip ? publicIp.properties.dnsSettings.fqdn : ''
output publicIp string = '' //contains(vm, 'pip') && vm.pip ? publicIp.properties.ipAddress : ''
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output principalId string = virtualMachine.identity.principalId
//output privateIps array = [ for i in range(0, count): nic[i].properties.ipConfigurations[0].properties.privateIPAddress ]
//output principalIds array = [ for i in range(0, count): virtualMachine[i].identity.principalId ]
