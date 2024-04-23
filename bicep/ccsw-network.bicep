targetScope = 'resourceGroup'

param location string = resourceGroup().location

param autogenerateSecrets bool
param useEnteredKey bool 
param useStoredKey bool
param adminUsername string
@secure()
param adminPassword string
param adminSshPublicKey string
param storedKey object = {}

//cc vm parameters
param ccVMSize string

param ccswConfig object

//FIX: Autogenerate scenario does not work, see TODO in publicKey.bicep
//TODO 
module ccswPublicKey './publicKey.bicep' = if (!useEnteredKey) {
  name: 'ccswPublicKey'
  params: {
    location: location
    autogenerateSecrets: autogenerateSecrets
    useStoredKey: useStoredKey
    storedKey: storedKey
  }
}
var publicKey = useEnteredKey ? adminSshPublicKey : ccswPublicKey.outputs.publicKey

//FIX: Currently works as expected for creating Vnets for user, but not for BYOV
module ccswNetwork './network-new.bicep' = {
  name: 'ccswNetwork'
  params: {
    location: location
    ccswConfig: ccswConfig

  }
}
