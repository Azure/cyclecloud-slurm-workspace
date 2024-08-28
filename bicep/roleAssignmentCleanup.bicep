targetScope = 'subscription'

param location string
param resourceGroup string
param vmName string = 'ccsw-cyclecloud'
param roles array = [
  'Contributor'
  'Storage Account Contributor'
  'Storage Blob Data Contributor'
]

var subscriptionId = split(subscription().id, '/')[2]


resource ccswResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroup
  location: location
}

output names array = [for role in roles: '/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleAssignments/${guid(vmName, role, ccswResourceGroup.id, subscription().id)}']
output subscriptionId string = subscriptionId
