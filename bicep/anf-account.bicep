targetScope = 'resourceGroup'

param location string
param resourcePostfix string = uniqueString(resourceGroup().id)

resource anfAccount 'Microsoft.NetApp/netAppAccounts@2025-12-01' = {
  name: 'hpcanfaccount-${take(resourcePostfix,10)}'
  location: location
}
