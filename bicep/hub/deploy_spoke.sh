#!/bin/bash 

cd "$(dirname "$0")"

# hub params
HUB_RG_NAME=""

# spoke params
LOCATION=""
SPOKE_NUMBER=""

# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -rg|--hub-resource-group)
            HUB_RG_NAME="$2"
            shift 2
            ;;
        -s|--spoke-number)
            SPOKE_NUMBER="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --hub-resource-group <hub resource group name> --location <Azure region> --spoke-number <nth spoke>"
            echo "       or: $0 -rg <hub resource group name> -l <Azure region> -s <nth spoke>"
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
if [ -z "$RESOURCE_GROUP" ] || [ -z "$LOCATION" ] || [ -z "$SPOKE_NUMBER" ]; then
    echo "Error: --resource-group, --location, --spoke-number are required."
    echo "Use --help for usage information."
    exit 1
fi

# hub
SUFFIX="-${HUB_RG_NAME}"

# spoke
SPOKE_RG_NAME="gb200-ccw-${LOCATION}-0${SPOKE_NUMBER}-rg"
SPOKE_DEPLOYMENT_NAME="spoke-ccw-0${SPOKE_NUMBER}"

if az deployment sub show -g -n "${SPOKE_DEPLOYMENT_NAME}" > /dev/null 2>&1; then
    RG_EXISTS=$(az group exists -n "$SPOKE_RG_NAME" | tr -d '\r\n')
    if [ "$RG_EXISTS" = "false" ]; then
        echo "Spoke #${SPOKE_NUMBER} already exists. Please set a new spoke number. Exiting."
        exit 0
    fi
fi

fetch_outputs() {
az deployment group show -g "$HUB_RG_NAME" -n "hub-vnet${SUFFIX}" --query properties.outputs > hub-vnet-outputs.json
az deployment group show -g "$HUB_RG_NAME" -n "hub-anf-resources${SUFFIX}" --query properties.outputs > hub-anf-outputs.json
az deployment group show -g "$HUB_RG_NAME" -n "hub-db${SUFFIX}" --query properties.outputs > hub-db-outputs.json
[ -f cyclecloud-monitoring/infra/outputs.json ] && cp cyclecloud-monitoring/infra/outputs.json hub-monitoring-outputs.json
# az deployment group show -g "$HUB_RG_NAME" -n ingestionEndpoint --query properties.outputs > hub-monitoring-outputs.json
}

fetch_outputs

cp original_spoke_params.json spoke_params.json

replace_fields() {
    jq "$1" spoke_params.json > tmp_spoke_params.json && mv tmp_spoke_params.json spoke_params.json
}

# shared FS
IP_ADDRESS=$(jq -r '.ipAddress.value' hub-anf-outputs.json)
EXPORT_PATH=$(jq -r '.exportPath.value' hub-anf-outputs.json)
MOUNT_OPTIONS=$(jq -r '.mountOptions.value' hub-anf-outputs.json)
replace_fields ".sharedFilesystem={ value: { type: \"nfs-existing\", ipAddress: \"$IP_ADDRESS\", exportPath: \"$EXPORT_PATH\", mountOptions: \"$MOUNT_OPTIONS\" } }"

# new vnet 
ADDRESS_SPACE="10.${SPOKE_NUMBER}.0.0/24"
replace_fields ".network.value.addressSpace=\"$ADDRESS_SPACE\""

# vnet to peer 
PEERED_VNET_ID=$(jq -r '.vnetId.value' hub-vnet-outputs.json)
PEERED_VNET_NAME=$(echo "${PEERED_VNET_ID}" | cut -d '/' -f9)
PEERED_VNET_LOCATION=$(az network vnet show -g "$RG" -n "$PEERED_VNET_NAME" --query location -o tsv | tr -d '\r\n')
replace_fields ".network.value.vnetToPeer={ name: \"$PEERED_VNET_NAME\", id: \"$PEERED_VNET_ID\", location: \"$PEERED_VNET_LOCATION\", subscriptionName: \"\"}"

# database config
DB_IP="10.0.0.228"
DB_USERNAME=$(jq -r '.adminUser.value' db_params.json)
DB_PASSWORD=$(jq -r '.adminPassword.value' db_params.json)
replace_fields ".databaseConfig={ value: { type: \"privateIp\", databaseUser: \"$DB_USERNAME\", privateIp: \"$DB_IP\" }}"
replace_fields ".databaseAdminPassword={ value: \"$DB_PASSWORD\" }"

# monitoring 
MONITORING_INGESTION_ENDPOINT=$([ -f hub-monitoring-outputs.json ] && jq -r '.properties.outputs.ingestionEndpoint.value' hub-monitoring-outputs.json || echo "")

az deployment sub create \
    --location "$LOCATION" \
    --template-file "$(pwd)/../mainTemplate.bicep" \
    --parameters "$(pwd)/spoke_params.json" \
    --parameters location="$LOCATION" \
    --parameters resourceGroup="${SPOKE_RG_NAME}" \
    --parameters ccVMName="ccw-${SPOKE_NUMBER}-cyclecloud-vm" \
    --parameters clusterName="ccw-${SPOKE_NUMBER}" \
    --parameters monitoringIngestionEndpoint="${MONITORING_INGESTION_ENDPOINT}" \
    --name "spoke-ccw-0${SPOKE_DEPLOYMENT_NAME}" 
 