param appName string = 'myEntraApp'
param displayName string = 'My Entra Application'
param signInAudience string = 'AzureADMyOrg'

resource app 'Microsoft.Graph/applications@v1.0' = {

}
//create managed identity for VMSSs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}


output managedIdentityId string = managedIdentity.id

output appId string = app.properties.appId
