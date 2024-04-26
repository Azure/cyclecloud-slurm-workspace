targetScope = 'subscription'

param location string 

param adminUsername string
@secure()
param adminPassword string
//param adminKeyphrase string
param adminSshPublicKey string = ''

//cc vm parameters
param ccVMSize string

param ccswConfig object

//force parameter files to work
param autogenerateSecrets bool
param useEnteredKey bool 
param useStoredKey bool
param storedKey object = {}
@secure()
param databaseAdminPassword string
//param databaseAdminKeyphrase string
param trash_for_arm_ttk object

resource ccswResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: ccswConfig.resource_group
  location: ccswConfig.location
}

module makeCCSWresources 'ccsw.bicep' = {
  name: 'pid-8d5b25bd-0ba7-49b9-90b3-3472bc08443e-partnercenter'
  scope: ccswResourceGroup
  params: {
    location: location
    adminUsername: adminUsername
    adminPassword: adminPassword
    adminSshPublicKey: adminSshPublicKey
    autogenerateSecrets: autogenerateSecrets
    useEnteredKey: useEnteredKey
    useStoredKey: useStoredKey
    storedKey: storedKey
    ccVMSize: ccVMSize
    ccswConfig: ccswConfig
    databaseAdminPassword: databaseAdminPassword
    trash_for_arm_ttk: trash_for_arm_ttk
  }
}
