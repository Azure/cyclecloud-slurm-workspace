#!/bin/bash
RESOURCE_GROUP_NAME=$1
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  echo "Usage: $0 <resource-group-name>"
  exit 1
fi

# Retrieve th location of the resource group
LOCATION=$(az group show --name $RESOURCE_GROUP_NAME --query location -o tsv)
if [ -z "$LOCATION" ]; then
  echo "Resource group $RESOURCE_GROUP_NAME does not exist."
  exit 1
fi

az deployment group create --resource-group $RESOURCE_GROUP_NAME --template-file main.bicep --parameters location=$LOCATION