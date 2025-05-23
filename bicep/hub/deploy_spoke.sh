#!/bin/bash 

cd "$(dirname "$0")"

RG="gb200-hub-westus2"
SUFFIX="-${RG}"
SPOKE_NUMBER="1"

fetch_outputs() {
az deployment group show -g "$RG" -n "hub-vnet${SUFFIX}" --query properties.outputs > hub-vnet-outputs.json
az deployment group show -g "$RG" -n "hub-anf-resources${SUFFIX}" --query properties.outputs > hub-anf-outputs.json
az deployment group show -g "$RG" -n "hub-db${SUFFIX}" --query properties.outputs > hub-db-outputs.json

# Monitoring NTS: Copy cc-monitoring outputs to directory containing hub outputs
# cp /path/to/outputs.json hub-monitoring-outputs.json

# TODO: blob storage
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
PEERED_VNET_NAME=$(echo $PEERED_VNET_ID | cut -d '/' -f9)
PEERED_VNET_LOCATION=$(az network vnet show -g "$RG" -n "$PEERED_VNET_NAME" --query location -o tsv | tr -d '\r\n')
replace_fields ".network.value.vnetToPeer={ name: \"$PEERED_VNET_NAME\", id: \"$PEERED_VNET_ID\", location: \"$PEERED_VNET_LOCATION\", subscriptionName: \"\"}"

# database config
DB_IP="10.0.0.228"
DB_USERNAME=$(jq -r '.adminUser.value' db_params.json)
DB_PASSWORD=$(jq -r '.adminPassword.value' db_params.json)
replace_fields ".databaseConfig={ value: { type: \"privateIp\", databaseUser: \"$DB_USERNAME\", privateIp: \"$DB_IP\" }}"
replace_fields ".databaseAdminPassword={ value: \"$DB_PASSWORD\" }"

LOCATION='westus2'
SPOKE_RG_NAME="gb200-ccw-${LOCATION}-0${SPOKE_NUMBER}-rg"
SPOKE_DEPLOYMENT_NAME="spoke-ccw-0${SPOKE_NUMBER}"

if az deployment sub show -g -n "${SPOKE_DEPLOYMENT_NAME}" > /dev/null 2>&1; then
    RG_EXISTS=$(az group exists -n "$SPOKE_RG_NAME" | tr -d '\r\n')
    if [ "$RG_EXISTS" = "false" ]; then
        echo "Spoke #${SPOKE_NUMBER} already exists. Please set a new spoke number. Exiting."
        exit 0
    fi
fi

az deployment sub create \
    --location "$LOCATION" \
    --template-file "$(pwd)/../mainTemplate.bicep" \
    --parameters "$(pwd)/spoke_params.json" \
    --parameters location="$LOCATION" \
    --parameters resourceGroup="${SPOKE_RG_NAME}" \
    --parameters ccVMName="ccw-${SPOKE_NUMBER}-cyclecloud-vm" \
    --parameters clusterName="ccw-${SPOKE_NUMBER}" \
    --name "spoke-ccw-0${SPOKE_DEPLOYMENT_NAME}" 
 