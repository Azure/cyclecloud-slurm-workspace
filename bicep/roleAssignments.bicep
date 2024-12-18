targetScope = 'subscription'

param roles array
param principalId string

var role_lookup = {
  Contributor: resourceId('microsoft.authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  UserAccessAdministrator: resourceId('microsoft.authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  'Storage Account Contributor': resourceId('microsoft.authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
  'Storage Blob Data Contributor': resourceId('microsoft.authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
}

resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [ for role in roles: {
  name: guid(subscription().id, principalId, role_lookup[role])
  properties: {
    roleDefinitionId: role_lookup[role]
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}]
