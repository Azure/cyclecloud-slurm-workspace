targetScope = 'subscription'

param principalId string
param principalType string

// Role assignment for the managed identity to read compute resources
resource skuValidationRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: principalId
    principalType: principalType
  }
}

output roleAssignmentId string = skuValidationRoleAssignment.id
