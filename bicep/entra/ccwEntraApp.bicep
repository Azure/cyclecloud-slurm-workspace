extension microsoftGraphV1
targetScope = 'resourceGroup'
// WARNING!!!
// If this file changes, you need to run `az bicep build -f bicep/entra/ccwEntraApp.bicep` and add the new json to the git commit.

// Creates a secret-less client application, using a user-assigned managed identity
// as the credential (configured as part of the application's federated identity credential).

param appName string
param umiName string
param fqdn string = 'OPEN_ONDEMAND_NIC_IP.PLACEHOLDER'
param cyclecloudVMIpAddress string = 'CYCLECLOUD_VM_IP.PLACEHOLDER'
param serviceManagementReference string = ''

var ccUserAccessGuid string = guid(resourceGroup().id, 'user_access')

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
resource ccwEntraManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: umiName
}

// Create a (client) application registration with a federated identity credential (FIC)
// The FIC is configured with the managed identity as the subject
// The application is listed under the "App registrations" in the Azure Portal
var appUniqueName = guid(subscription().id, resourceGroup().id, appName) // Need to be unique inside the tenant because recreating with the same name will fail if the app is manually deleted
var superUserRoleId = guid(resourceGroup().id, 'superuser')
resource ccwEntraApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: appName
  uniqueName: appUniqueName
  serviceManagementReference: !empty(serviceManagementReference) ? serviceManagementReference : null

  resource myMsiFic 'federatedIdentityCredentials@v1.0' = {
    name: '${ccwEntraApp.uniqueName}/msiAsFic'
    description: 'Trust the Open OnDemand\'s user-assigned MI as a credential for the application'
    audiences: [
       audiences[cloudEnvironment].uri
    ]
    issuer: issuer
    subject: ccwEntraManagedIdentity.properties.principalId
  }

  // begin Authentication section
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

  // single-page application settings
  spa: {
    redirectUris: [
      uri('https://${cyclecloudVMIpAddress}','/login')
      uri('https://${cyclecloudVMIpAddress}','/home')
    ]
  }

  publicClient: {
    redirectUris:[
      'http://localhost'
      'https://localhost'
    ]
  }

  isFallbackPublicClient: true
  // end Authentication section

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

  // begin App Roles section
  appRoles: [
    {
      allowedMemberTypes: [
        'User'
				'Application'
			]
			description: 'CycleCloud Administrator'
			displayName: 'Administrator'
			id: guid(resourceGroup().id, 'administrator')
			isEnabled: true
			value: 'Administrator'
		}
    {
      allowedMemberTypes: [
        'User'
        'Application'
      ]
      description: 'CycleCloud SuperUser'
      displayName: 'SuperUser'
      id: superUserRoleId
      isEnabled: true
      value: 'SuperUser'
		}
		{
			allowedMemberTypes: [
				'User'
				'Application'
			]
			description: 'CycleCloud User'
			displayName: 'User'
			id: guid(resourceGroup().id, 'user')
			isEnabled: true
			value: 'User'
		}
  ]
  // end App Roles section
}

var clientAppId = ccwEntraApp.appId

resource updateApplication 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appUniqueName
  displayName: appName
  serviceManagementReference: !empty(serviceManagementReference) ? serviceManagementReference : null

  // begin API Permissions Section
  api: {
    oauth2PermissionScopes: [
      {
        adminConsentDescription: 'Azure CycleCloud Workspace for Slurm with Entra ID authentication'
        adminConsentDisplayName: 'CycleCloud can access the user profile & use it to log into the web application.'
        id: ccUserAccessGuid
        isEnabled: true
        //lang: null
        //origin: 'Application'
        type: 'User'
        userConsentDescription: null
        userConsentDisplayName: null
        value: 'user_access'
      }
    ]

    requestedAccessTokenVersion: 1
  }

  requiredResourceAccess: [
    { // This is the custom API permission for CycleCloud
      resourceAppId: clientAppId
      resourceAccess: [ 
        {
          id: ccUserAccessGuid
          type: 'Scope'
        }
      ]
    }
    { // Microsoft Graph API
      resourceAppId: graphAppId
      resourceAccess: [ for (scope,i) in appScopes: {
          id: filter(graphScopes, graphScopes => graphScopes.value == scope)[0].id
          type: 'Scope'
        }
      ]
    }
  ]
  // end API Permissions section

  // begin Expose an API section
  identifierUris: [
    'api://${clientAppId}'
  ]
  // end Expose an API section

  dependsOn: [
    ccwEntraApp
  ]
}

resource servicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: clientAppId
}

// assign "Super User" app role to user who ran the deployment
resource superUserAssignment 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  appRoleId: superUserRoleId
  resourceId: servicePrincipal.id
  principalId: deployer().objectId
}

// outputs
output ccwEntraClientTenantId string = tenant().tenantId
output ccwEntraClientAppId string = clientAppId
output ccwEntraMiId string = ccwEntraManagedIdentity.id
