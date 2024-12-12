#!/bin/bash
set -e

DELETE_RG=0
RG=""
VM=""
HELP=0

while (( "$#" )); do
    case "$1" in
        -d|--delete-resource-group)
            DELETE_RG=1
            shift 1
            ;;
        -rg|--resource-group)
            RG=$2
            shift 2
            ;;
        -vm|--virtual-machine)
            VM=$2
            shift 2
            ;;
        --help)
            HELP=1
            shift
            ;;
        -*|--*=)
            echo "Unknown option $1" >&2
            HELP=1
            shift
            ;;
        *)
            echo "Unknown option  $1" >&2
            HELP=1
            shift
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$RG" ] ; then
    echo "Please ensure that --resource-group is provided" >&2
    HELP=1
fi

if [ -z "$VM" ] ; then
    echo "Please ensure that --virtual-machine is provided" >&2
    HELP=1
fi

if [ $HELP == 1 ]; then
    echo Usage: delete_roles.sh --resource-group RG --virtual-machine VM [--delete-resource-group] 1>&2
    exit 1
fi

LOCATION=$(az group show -n $RG --query location -o tsv 2>/dev/null | tr -d '\n' | tr -d '\r') 
if [ -z "$LOCATION" ]; then
    LOCATION='eastus'
fi
echo Resource group $RG is in location $LOCATION
RG_PATH=util/${RG}
mkdir -p $RG_PATH
CLEANUP_JSON_PATH=${RG_PATH}/.role_assignment_cleanup.json
CLEANUP_OUTOUT_JSON_PATH=${RG_PATH}/.role_assignment_cleanup_output.json

cat > $CLEANUP_JSON_PATH<<EOF
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "value": "$LOCATION"
        },
        "resourceGroup": {
            "value": "$RG"
        },
        "vmName": {
            "value": "$VM"
        }
    }
}
EOF

echo Recreating resource group $RG to get the GUIDs of the roles created in the initial CCW deployment
az deployment sub create --location $LOCATION --template-file ./bicep/roleAssignmentCleanup.bicep -n $RG-cleanup-$LOCATION --parameters $CLEANUP_JSON_PATH > $CLEANUP_OUTOUT_JSON_PATH

assignment_names=$(cat $CLEANUP_OUTOUT_JSON_PATH | jq -r ".properties.outputs.names.value[]")
echo Deleting, if they exist, the following role IDs: $assignment_names

az role assignment delete --ids $assignment_names

if [ $DELETE_RG == 1 ]; then
    echo Deleting the resource group $RG
    az group delete -n $RG -y
    echo Done
fi

echo Cleaning up temporary files under util/
rm -rf ${RG_PATH}
echo Done! You should be able to redeploy using this resource group or resource group name
