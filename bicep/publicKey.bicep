param storedKeyId string

resource storedPublicKey 'Microsoft.Compute/sshPublicKeys@2024-03-01' existing = {
  name: split(storedKeyId,'/')[8]
  scope: resourceGroup(split(storedKeyId,'/')[4])
}

var publicKey = storedPublicKey.properties.publicKey
output publicKey string = publicKey
