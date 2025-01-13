extension microsoftGraphV1
targetScope = 'resourceGroup'
param location string

// Creates a secret-less client application, using a user-assigned managed identity
// as the credential (configured as part of the application's federated identity credential).

param name string
param redirectURI string = 'https://ood-fqdn/oidc' // Redirect URI for OIDC

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
// create a user assigned managed identity to be assigned to the OOD VM
resource oodManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${name}-mi'
  location: location
}

// Create a (client) application registration with a federated identity credential (FIC)
// The FIC is configured with the managed identity as the subject
// The application is listed under the "App registrations" in the Azure Portal
resource oodApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: '${name}-app'
  uniqueName: guid(subscription().id, resourceGroup().id, name) // Need to be unique inside the tenant, issue is if you manually delete the app, it will failed if you recreate it with the same name

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
        uri: redirectURI
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
