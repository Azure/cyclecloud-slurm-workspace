#!/bin/bash
set -e

cd "$(dirname "$0")/.." 

# Initialize variables
RESOURCE_GROUP=""
LOCATION=""
APPLY_ROLE_ASSIGNMENTS=true

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
        --no-role-assignments)
            APPLY_ROLE_ASSIGNMENTS=false
            shift
            ;;
        -h|--help)
            # TODO AGB: Clean up 
            echo "Usage: $0 --resource-group <resource group name> --location <Azure region> [--no-role-assignments]"
            echo "       or: $0 -rg <resource group name> -l <Azure region> [--no-role-assignments]"
            echo "       --no-role-assignments: Do not apply role assignments to the managed identities."
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

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

echo Deploying storage account to resource group "${RESOURCE_GROUP}" in location "${LOCATION}"...
STORAGE_DEPLOYMENT_NAME="ccw-storage-deployment-${RESOURCE_GROUP}-${LOCATION}"
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file $(pwd)/bicep/storage-new.bicep \
    --parameters location="$LOCATION" \
    --name "$STORAGE_DEPLOYMENT_NAME"

STORAGE_ACCOUNT_NAME=$(az deployment group show -g "$RESOURCE_GROUP" -n "$STORAGE_DEPLOYMENT_NAME" --query "properties.outputs.storageAccountName.value" -o tsv | tr -d '\r\n')

echo Creating managed identity for virtual machine scale sets in resource group "${RESOURCE_GROUP}" in location "${LOCATION}"...
if [ "$APPLY_ROLE_ASSIGNMENTS" = true ]; then
    echo "Role assignments will be applied after the managed identity is created."
else
    echo "Role assignments will NOT be applied as requested."
fi
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file $(pwd)/bicep/vmssManagedIdentity.bicep \
    --parameters name="ccwLockerManagedIdentity" \
    --parameters location="$LOCATION" \
    --parameters storageAccountName="$STORAGE_ACCOUNT_NAME" \
    --parameters applyRoleAssignments="$APPLY_ROLE_ASSIGNMENTS" \
    --name "ccw-vmss-mi-deployment-${RESOURCE_GROUP}-${LOCATION}"

echo Creating managed identity for the CycleCloud virtual machine in resource group "${RESOURCE_GROUP}" in location "${LOCATION}"...
if [ "$APPLY_ROLE_ASSIGNMENTS" = true ]; then
    echo "Role assignments will be applied after the managed identity is created."
else
    echo "Role assignments will NOT be applied as requested."
fi
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file $(pwd)/bicep/vmManagedIdentity.bicep \
    --parameters location="$LOCATION" \
    --parameters applyRoleAssignments="$APPLY_ROLE_ASSIGNMENTS" \
    --name "ccw-vm-mi-deployment-${RESOURCE_GROUP}-${LOCATION}"