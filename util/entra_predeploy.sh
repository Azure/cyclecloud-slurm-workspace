#!/bin/bash 
set -e

LOCATION=<>
ENTRA_MI_RESOURCE_GROUP=<>
MI_NAME=<>
APP_NAME=<>
SERVICE_MANAGEMENT_REFERENCE=""

ENTRA_DEPLOYMENT_NAME="${APP_NAME}-${ENTRA_MI_RESOURCE_GROUP}-${LOCATION}"
az group create -l $LOCATION -n $ENTRA_MI_RESOURCE_GROUP
az identity create --name $MI_NAME --resource-group $ENTRA_MI_RESOURCE_GROUP --location $LOCATION

# Build parameters for deployment
DEPLOYMENT_PARAMS="appName=${APP_NAME} umiName=${MI_NAME}"
if [ -n "${SERVICE_MANAGEMENT_REFERENCE}" ]; then
    DEPLOYMENT_PARAMS="${DEPLOYMENT_PARAMS} serviceManagementReference=${SERVICE_MANAGEMENT_REFERENCE}"
fi

az deployment group create -g $ENTRA_MI_RESOURCE_GROUP --template-uri https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/refs/tags/2025.12.01/bicep/entra/ccwEntraApp.json --parameters ${DEPLOYMENT_PARAMS} --name ${ENTRA_DEPLOYMENT_NAME}

ENTRA_TENANT_ID=$(az deployment group show --name $ENTRA_DEPLOYMENT_NAME --resource-group $ENTRA_MI_RESOURCE_GROUP --query properties.outputs.ccwEntraClientTenantId.value -o tsv)
ENTRA_CLIENT_ID=$(az deployment group show --name $ENTRA_DEPLOYMENT_NAME --resource-group $ENTRA_MI_RESOURCE_GROUP --query properties.outputs.ccwEntraClientAppId.value -o tsv)
ENTRA_MI_RESOURCE_ID=$(az deployment group show --name $ENTRA_DEPLOYMENT_NAME --resource-group $ENTRA_MI_RESOURCE_GROUP --query properties.outputs.ccwEntraMiId.value -o tsv)
echo "Use the following values to create Azure CycleCloud Workspace for Slurm with Entra ID authentication"
echo "Tenant ID: ${ENTRA_TENANT_ID}"
echo "Client ID: ${ENTRA_CLIENT_ID}"
echo "Managed Identity Resource ID: ${ENTRA_MI_RESOURCE_ID}"