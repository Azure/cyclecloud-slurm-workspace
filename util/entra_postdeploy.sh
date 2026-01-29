#!/bin/bash
set -e

CCW_RESOURCE_GROUP=""
HELP=0


while [ "$#" -gt 0 ]; do
    case "$1" in
        -rg|--ccw-resource-group)
            CCW_RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            HELP=1
            shift
            ;;
        -*)
            echo "Unknown option $1" >&2
            HELP=1
            shift
            ;;
        *)
            echo "Unknown argument $1" >&2
            HELP=1
            shift
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$CCW_RESOURCE_GROUP" ] ; then
    echo "Please ensure that --ccw-resource-group is provided" >&2
    HELP=1
    exit 1
fi

if [ $HELP = 1 ]; then
    echo "Usage: entra_postdeploy.sh --ccw-resource-group <resource-group>" 1>&2
    exit 1
fi

CCW_DEPLOYMENT_NAME='pid-d5d2708b-a4ef-42c0-a89b-b8bd6dd6d29b-partnercenter'
CCW_VM_DEPLOYMENT_NAME='ccwVM-cyclecloud'

CCW_VM_PRIVATE_IP=$(az deployment group show --name $CCW_VM_DEPLOYMENT_NAME --resource-group $CCW_RESOURCE_GROUP --query properties.outputs.privateIp.value -o tsv | tr -d '\n' | tr -d '\r')
ENTRA_APP_CLIENT_ID=$(az deployment group show --name $CCW_DEPLOYMENT_NAME --resource-group $CCW_RESOURCE_GROUP --query properties.outputs.entraIdInfo.value.clientId -o tsv | tr -d '\n' | tr -d '\r')

# 1. Get existing URIs (or empty array if none)
EXISTING_SPA_URIS=$(az ad app show --id "$ENTRA_APP_CLIENT_ID" --query "spa.redirectUris" -o json)
[ "$EXISTING_SPA_URIS" = "" ] && EXISTING_SPA_URIS="[]"
# 2. Append new URIs
UPDATED_SPA_URI_LIST=$(echo "$EXISTING_SPA_URIS" | jq --arg ip "$CCW_VM_PRIVATE_IP" '. + ["https://\($ip)/home","https://\($ip)/sso"] | unique')
# 3. Update the app
az ad app update --id "$ENTRA_APP_CLIENT_ID" --set "spa={\"redirectUris\": $UPDATED_SPA_URI_LIST}"

echo "Updated Entra ID Application (Client ID: $ENTRA_APP_CLIENT_ID) with CycleCloud VM private IP redirect URIs."

# TODO The below is the same thing as above, so make the steps into functions?
# Remember, OOD URI query is web.redirectUris rather than spa.redirectUris
# Idea: function takes in arrays of [private IP, uri type] and conditionally applies suffixes e.g. /home /login /oidc
DEPLOY_OOD_TYPE=$(az deployment group show --name $CCW_DEPLOYMENT_NAME --resource-group $CCW_RESOURCE_GROUP --query properties.outputs.ood.value.type -o tsv | tr -d '\n' | tr -d '\r')
if [ "$DEPLOY_OOD_TYPE" = "enabled" ]; then
    OOD_DEPLOYMENT_NAME='ccwOpenOnDemandNIC'
    OOD_VM_PRIVATE_IP=$(az deployment group show --name $OOD_DEPLOYMENT_NAME --resource-group $CCW_RESOURCE_GROUP --query properties.outputs.privateIp.value -o tsv | tr -d '\n' | tr -d '\r')

    # 1. Get existing URIs (or empty array if none)
    EXISTING_WEB_URIS=$(az ad app show --id "$ENTRA_APP_CLIENT_ID" --query "web.redirectUris" -o json)
    [ "$EXISTING_WEB_URIS" = "null" ] && EXISTING_WEB_URIS="[]"
    # 2. Append new URIs
    UPDATED_WEB_URI_LIST=$(echo "$EXISTING_WEB_URIS" | jq --arg ip "$OOD_VM_PRIVATE_IP" '. + ["https://\($ip)/oidc"] | unique')
    # 3. Update the app
    az ad app update --id "$ENTRA_APP_CLIENT_ID" --set "web={\"redirectUris\": $UPDATED_WEB_URI_LIST}"

    echo "Updated Entra ID Application (Client ID: $ENTRA_APP_CLIENT_ID) with Open OnDemand VM private IP redirect URIs."
fi