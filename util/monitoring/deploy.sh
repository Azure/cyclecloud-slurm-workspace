#!/bin/bash
RESOURCE_GROUP_NAME=$1
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  echo "Usage: $0 <resource-group-name>"
  exit 1
fi

# Retrieve the location of the resource group
LOCATION=$(az group show --name $RESOURCE_GROUP_NAME --query location -o tsv)
if [ -z "$LOCATION" ]; then
  echo "Resource group $RESOURCE_GROUP_NAME does not exist."
  exit 1
fi

# Retrieve the user object id of the current user doing the deployment
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
if [ -z "$USER_OBJECT_ID" ]; then
  echo "Failed to retrieve user object ID."
  exit 1
fi

az deployment group create --resource-group $RESOURCE_GROUP_NAME --template-file main.bicep --parameters location=$LOCATION userObjectId=$USER_OBJECT_ID > outputs.json
if [ $? -ne 0 ]; then
  echo "Deployment failed."
  exit 1
fi
# Check if the deployment was successful
if grep -q '"provisioningState": "Succeeded"' outputs.json; then
  echo "Deployment succeeded."
else
  echo "Deployment failed."
  exit 1
fi

# Assign the Monitoring Metrics Publisher role to the User Managed Identity
UMI_PID=$(jq -r '.properties.outputs.managedIdentityPrincipalId.value' outputs.json)
DCR_ID=$(jq -r '.properties.outputs.dcrResourceId.value' outputs.json)
az role assignment create --role 'Monitoring Metrics Publisher' \
                              --assignee ${UMI_PID} \
                              --scope ${DCR_ID}
if [ $? -ne 0 ]; then
  echo "Failed to assign role to User Managed Identity."
  exit 1
fi
