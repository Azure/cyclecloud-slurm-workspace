#!/bin/bash 
set -e
cd "$(dirname "$0")"

# convert base64 files
pushd "$(dirname "$0")/../../"
./init.sh
popd


# hub params
HUB_RG_NAME=""

# spoke params
LOCATION=""
SPOKE_NUMBER=""

WHATIF=false

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
        --what-if)
            WHATIF=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --hub-resource-group <hub resource group name> --location <Azure region> --spoke-number <spoke number> [--what-if]"
            echo "       or: $0 -rg <hub resource group name> -l <Azure region> -s <spoke number> [--what-if]"
            echo "       --what-if: Perform a what-if deployment without making changes."
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
if [ -z "$HUB_RG_NAME" ] || [ -z "$LOCATION" ] || [ -z "$SPOKE_NUMBER" ]; then
    echo "Error: --resource-group, --location, --spoke-number are required."
    echo "Use --help for usage information."
    exit 1
fi

WHATIF_FLAG=""
if [ "$WHATIF" = true ]; then
    WHATIF_FLAG="--what-if"
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
    mkdir -p outputs
    if [ -f outputs/hub-vnet-outputs.json ]; then
        echo "outputs/hub-vnet-outputs.json already fetched. Skipping."
    else
        echo "Fetching outputs for hub vnet..."
        az deployment group show -g "$HUB_RG_NAME" -n "hub-vnet${SUFFIX}" --query properties.outputs > outputs/hub-vnet-outputs.json.tmp
        mv outputs/hub-vnet-outputs.json.tmp outputs/hub-vnet-outputs.json
    fi

    if [ -f outputs/hub-mi-outputs.json ]; then
        echo "outputs/hub-mi-outputs.json already fetched. Skipping."
    else
        echo "Fetching outputs for hub managed identity..."
        az deployment group show -g "$HUB_RG_NAME" -n "${HUB_RG_NAME}-hub-mi" --query properties.outputs > outputs/hub-mi-outputs.json.tmp
        mv outputs/hub-mi-outputs.json.tmp outputs/hub-mi-outputs.json
    fi

    if [ -f outputs/hub-anf-outputs.json ]; then
        echo "outputs/hub-anf-outputs.json already fetched. Skipping."
    else
        echo "Fetching outputs for hub ANF..."
        az deployment group show -g "$HUB_RG_NAME" -n "hub-anf-resources${SUFFIX}" --query properties.outputs > outputs/hub-anf-outputs.json.tmp
        mv outputs/hub-anf-outputs.json.tmp outputs/hub-anf-outputs.json
    fi
    if [ -f outputs/hub-db-outputs.json ]; then
        echo "outputs/hub-db-outputs.json already fetched. Skipping."
    else
        echo "Fetching outputs for hub MySQL database..."
        az deployment group show -g "$HUB_RG_NAME" -n "hub-db${SUFFIX}" --query properties.outputs > outputs/hub-db-outputs.json.tmp
        mv outputs/hub-db-outputs.json.tmp outputs/hub-db-outputs.json
    fi
    #if [ -f outputs/hub-monitoring-outputs.json ]; then
    #    echo "outputs/hub-monitoring-outputs.json already fetched. Skipping."
    #else
    #    echo "Fetching outputs for hub monitoring..."
    #    [ -f build/cyclecloud-monitoring/infra/outputs.json ] && cp build/cyclecloud-monitoring/infra/outputs.json outputs/hub-monitoring-outputs.json
    #    # az deployment group show -g "$HUB_RG_NAME" -n ingestionEndpoint --query properties.outputs > outputs/hub-monitoring-outputs.json
    #fi
    echo "Done fetching outputs."
}

fetch_outputs

# copy original spoke params, as a working copy
cp params/base_spoke_params.json spoke_params.json

replace_fields() {
    jq "$1" spoke_params.json > tmp_spoke_params.json && mv tmp_spoke_params.json spoke_params.json
}

# shared FS
IP_ADDRESS=$(jq -r '.ipAddress.value' outputs/hub-anf-outputs.json)
EXPORT_PATH=$(jq -r '.exportPath.value' outputs/hub-anf-outputs.json)
MOUNT_OPTIONS=$(jq -r '.mountOptions.value' outputs/hub-anf-outputs.json)
replace_fields ".sharedFilesystem={ value: { type: \"nfs-existing\", ipAddress: \"$IP_ADDRESS\", exportPath: \"$EXPORT_PATH\", mountOptions: \"$MOUNT_OPTIONS\" } }"

# new vnet 
ADDRESS_SPACE="10.${SPOKE_NUMBER}.0.0/24"
replace_fields ".network.value.addressSpace=\"$ADDRESS_SPACE\""

# vnet to peer 
PEERED_VNET_ID=$(jq -r '.vnetId.value' outputs/hub-vnet-outputs.json)
PEERED_VNET_NAME=$(echo "${PEERED_VNET_ID}" | cut -d '/' -f9)

PEERED_VNET_LOCATION=$(az network vnet show -g "$HUB_RG_NAME" -n "$PEERED_VNET_NAME" --query location -o tsv | tr -d '\r\n')
replace_fields ".network.value.vnetToPeer={ name: \"$PEERED_VNET_NAME\", id: \"$PEERED_VNET_ID\", location: \"$PEERED_VNET_LOCATION\", subscriptionName: \"\"}"

# database config
DB_IP="10.0.0.228"
DB_USERNAME=$(jq -r '.adminUser.value' params/db_params.json)
DB_PASSWORD=$(jq -r '.adminPassword.value' params/db_params.json)
replace_fields ".databaseConfig={ value: { type: \"privateIp\", databaseUser: \"$DB_USERNAME\", privateIp: \"$DB_IP\" }}"
replace_fields ".databaseAdminPassword={ value: \"$DB_PASSWORD\" }"

# monitoring 
# MONITORING_INGESTION_ENDPOINT=$(jq -r '.ingestionEndpoint.value' outputs/hub-monitoring-outputs.json)
# MONITORING_CLIENT_ID=$(jq -r '.hubMIClientId.value' outputs/hub-mi-outputs.json)
# if [ -z "$MONITORING_INGESTION_ENDPOINT" ] || [ -z "$MONITORING_CLIENT_ID" ]; then
#     echo "Monitoring ingestion endpoint or client ID not set. Please edit the script to set them directly until hub MI automation is implemented."
#     exit 1
# fi

# replace_fields ".monitoringIngestionEndpoint.value=\"$MONITORING_INGESTION_ENDPOINT\""
# replace_fields ".monitoringIdentityClientId.value=\"$MONITORING_CLIENT_ID\""


HUB_MI=$(jq -r '.hubMI.value' outputs/hub-mi-outputs.json)
replace_fields ".hubMI.value=\"$HUB_MI\""

echo "Deploying spoke #${SPOKE_NUMBER} in resource group ${SPOKE_RG_NAME} at location ${LOCATION}... ${WHATIF_FLAG}"
az deployment sub create \
   --location "$LOCATION" \
   --template-file "$(pwd)/../mainTemplate.bicep" \
   --parameters "$(pwd)/spoke_params.json" \
   --parameters location="$LOCATION" \
   --parameters resourceGroup="${SPOKE_RG_NAME}" \
   --parameters ccVMName="ccw-${SPOKE_NUMBER}-cyclecloud-vm" \
   --parameters clusterName="ccw-${SPOKE_NUMBER}" \
   --parameters monitoringIngestionEndpoint="${MONITORING_INGESTION_ENDPOINT}" \
   --name "spoke-ccw-0${SPOKE_DEPLOYMENT_NAME}" \
   $WHATIF_FLAG

 
