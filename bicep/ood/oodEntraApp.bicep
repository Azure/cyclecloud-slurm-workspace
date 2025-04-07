extension microsoftGraphV1
targetScope = 'resourceGroup'
// WARNING!!!
// If this file changes, you need to run `az build -f bicep/ood/oodEntraApp.bicep` and add the new json to the git commit.

// Creates a secret-less client application, using a user-assigned managed identity
// as the credential (configured as part of the application's federated identity credential).

param appName string
param umiName string
param fqdn string

// NOTE: Microsoft Graph Bicep file deployment is only supported in Public Cloud
var audiences = {
  AzureCloud: {
    uri: 'api://AzureADTokenExchange'
  }
  AzureUSGovernment: {
    uri: 'api://AzureADTokenExchangeUSGov'
  }
  USNat: {
    uri: 'api://AzureADTokenExchangeUSNat'
  }
  USSec: {
    uri: 'api://AzureADTokenExchangeUSSec'
  }
  AzureChinaCloud: {
    uri: 'api://AzureADTokenExchangeChina'
  }
}

var cloudEnvironment = environment().name
// login endpoint and tenant ID and issuer
var loginEndpoint = environment().authentication.loginEndpoint
var tenantId = tenant().tenantId
var issuer = '${loginEndpoint}${tenantId}/v2.0'
var graphAppId = '00000003-0000-0000-c000-000000000000'
var appScopes = ['profile','User.Read'] // this is required for OIDC auth

// Find Graph based on well-known appId
resource msGraphSP 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: graphAppId
}
var graphScopes = msGraphSP.oauth2PermissionScopes

// Retrieve the user assigned managed identity assigned to the OOD VM
resource oodManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: umiName
}

// Create a (client) application registration with a federated identity credential (FIC)
// The FIC is configured with the managed identity as the subject
// The application is listed under the "App registrations" in the Azure Portal
resource oodApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: appName
  uniqueName: guid(subscription().id, resourceGroup().id, appName) // Need to be unique inside the tenant, issue is if you manually delete the app, it will failed if you recreate it with the same name
  serviceManagementReference: '0a914b56-486a-4979-b994-7b85132f8f0f' // CycleCloud Service Tree ID

  resource myMsiFic 'federatedIdentityCredentials@v1.0' = {
    name: '${oodApp.uniqueName}/msiAsFic'
    description: 'Trust the Open OnDemand\'s user-assigned MI as a credential for the application'
    audiences: [
       audiences[cloudEnvironment].uri
    ]
    issuer: issuer
    subject: oodManagedIdentity.properties.principalId
  }

  web: {
    implicitGrantSettings: {
      enableAccessTokenIssuance: false
      enableIdTokenIssuance: true
    }
    redirectUriSettings: [
      {
        index: 0
        uri: uri('https://${fqdn}','/oidc')
      }
    ]
  }

  optionalClaims: {
    idToken: [
      {
        additionalProperties: []
        essential: false
        name: 'upn'
        source: null
      }
    ]
  }

  // This is to define API permissions under App registration -> API permission in the Azure Portal
  requiredResourceAccess: [
    {
      resourceAppId: graphAppId
      resourceAccess: [ for (scope,i) in appScopes: {
          id: filter(graphScopes, graphScopes => graphScopes.value == scope)[0].id
          type: 'Scope'
        }
      ]
    }
  ]
}

// outputs
output oodClientAppId string = oodApp.appId
output oodMiId string = oodManagedIdentity.id
