targetScope = 'subscription'

param location string
param infrastructureOnly bool = false

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

// build.sh will override this, but for development please set this yourself as a parameter
param branch string = 'main'
// This needs to be updated on each release. Our Cloud.Project records require a release tag
param project_version string = '2024.06.06'

//param databaseAdminKeyphrase string
param trash_for_arm_ttk object

resource ccswResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: ccswConfig.resource_group
  location: ccswConfig.location
  tags: contains(ccswConfig.tags, 'Microsoft.Resources/resourceGroups') ? ccswConfig.tags['Microsoft.Resources/resourceGroups'] : {}
}

module makeCCSWresources 'ccsw.bicep' = {
  name: 'pid-8d5b25bd-0ba7-49b9-90b3-3472bc08443e-partnercenter'
  scope: ccswResourceGroup
  params: {
    location: location
    infrastructureOnly: infrastructureOnly
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
    branch: branch
    project_version: project_version
    trash_for_arm_ttk: trash_for_arm_ttk
  }
}
