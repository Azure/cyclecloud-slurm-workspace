#!/bin/bash

# Initialize variables
RESOURCE_GROUP=""
LOCATION=""

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -rg|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --resource-group <resource group name> --location <Azure region>"
            echo "       or: $0 -rg <resource group name> -l <Azure region>"
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$RESOURCE_GROUP" ] || [ -z "$LOCATION" ]; then
    echo "Error: Both --resource-group and --location are required."
    echo "Use --help for usage information."
    exit 1
fi

cd "$(dirname "$0")"

# Check if the resource group exists and create it if it doesn't
RG_EXISTS=$(az group exists -n "$RESOURCE_GROUP" | tr -d '\r\n')
if [ "$RG_EXISTS" = "false" ]; then
    echo "Resource group '$RESOURCE_GROUP' does not exist. Creating it in location '$LOCATION'."
    az group create -n "$RESOURCE_GROUP" -l "$LOCATION"
    
    while RG_CREATED=$(az group exists -n "$RESOURCE_GROUP" | tr -d '\r\n'); [ "$RG_CREATED" = "false" ]; do
        echo "Waiting for resource group '$RESOURCE_GROUP' to be created..."
        sleep 1
    done
fi

# Deploy vnet
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$(pwd)/hub-vnet.bicep" \
    --parameters "$(pwd)/vnet_params.json" \
    --parameters location="$LOCATION" \
    --name hub-vnet

exit 0

# Deploy MySQL server 
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file ../mysql.bicep \
    --parameters db_params.json \
    --name hub-db

# Deploy Azure NetApp Files
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file ../anfs.bicep \
    --parameters '{ \"location\": { \"value\": \"${LOCATION}\" } }' \
    --name hub-anf-account
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file ../anf.bicep \
    --parameters anf_params.json \
    --name hub-anf-volume