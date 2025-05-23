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
echo Checking if resource group "${RESOURCE_GROUP}" exists...
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
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "$(pwd)/hub-vnet.bicep" \
    --parameters "$(pwd)/vnet_params.json" \
    --parameters location="$LOCATION" \
    --name "hub-vnet-${RESOURCE_GROUP}"

echo "Virtual network deployment is complete. Please enter the Azure Portal to create a VPN Gateway while the remainder of this script runs."

# Deploy Bastion
bastion_subnet_id=$(az network vnet subnet show -g "${RESOURCE_GROUP}" -n AzureBastionSubnet --vnet-name "hub-vnet-${RESOURCE_GROUP}" | jq '.id' | tr -d '"')
az deployment group create \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "$(pwd)/../bastion.bicep" \
    --parameters "$(pwd)/bastion_params.json" \
    --parameters location="${LOCATION}" \
    --parameters subnetId="${bastion_subnet_id}" \
    --name "hub-bastion-${RESOURCE_GROUP}"

# Deploy MySQL server 
db_subnet_id=$(az network vnet subnet show -g "${RESOURCE_GROUP}" -n database --vnet-name "hub-vnet-${RESOURCE_GROUP}" | jq '.id' | tr -d '"')
az deployment group create \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "$(pwd)/../mysql.bicep" \
    --parameters "$(pwd)/db_params.json" \
    --parameters location="${LOCATION}" \
    --parameters subnetId="${db_subnet_id}" \
    --name "hub-db-${RESOURCE_GROUP}"

# Deploy Azure NetApp Files
netapp_subnet_id=$(az network vnet subnet show -g "${RESOURCE_GROUP}" -n netapp --vnet-name "hub-vnet-${RESOURCE_GROUP}" | jq '.id' | tr -d '"')
az deployment group create \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "$(pwd)/../anf-account.bicep" \
    --parameters location="${LOCATION}" \
    --name "hub-anf-account-${RESOURCE_GROUP}"
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$(pwd)/../anf.bicep"\
    --parameters "$(pwd)/anf_params.json" \
    --parameters subnetId="${netapp_subnet_id}" \
    --parameters location="${LOCATION}" \
    --parameters name="shared" \
    --name "hub-anf-resources-${RESOURCE_GROUP}"

# Deploy monitoring
MONITORING_PROJECT_VERSION="1.0.0"
rm -rf cyclecloud-monitoring
git clone --branch "${MONITORING_PROJECT_VERSION}" https://github.com/Azure/cyclecloud-monitoring.git

cd cyclecloud-monitoring/infra
sh $(pwd)/deploy.sh "$RESOURCE_GROUP" 
cd ../..
