#!/bin/bash
set -e

DELETE_RG=0
RG=""
LOCATION=""
HELP=0

while (( "$#" )); do
    case "$1" in
        --delete-resource-group)
            DELETE_RG=1
            shift 1
            ;;
        --resource-group)
            RG=$2
            shift 2
            ;;
        --location)
            LOCATION=$2
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

if [ $HELP == 1 ]; then
    echo Usage: delete_roles.sh --resource-group RG --location LOCATION [--delete-resource-group] 1>&2
    exit 1
fi

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
        }
    }
}
EOF

echo recreating resource group $RG so that we can get the GUIDs of the roles we created
az deployment sub create --location $LOCATION --template-file ./bicep/roleAssignmentCleanup.bicep -n $RG-cleanup --parameters $CLEANUP_JSON_PATH > $CLEANUP_OUTOUT_JSON_PATH

assignment_names=$(cat $CLEANUP_OUTOUT_JSON_PATH | jq -r ".properties.outputs.names.value[]")
echo Deleting, if they exist, the following role names: $assignment_names

az role assignment delete --ids $assignment_names

if [ $DELETE_RG == 1 ]; then
    echo deleting the resource group
    az group delete -n $RG -y
    echo done
fi

echo cleaning up temporary files under util/
rm -rf ${RG_PATH}
echo done! You should be able to redeploy using this resource group or resource group name.
