#!/bin/bash
set -e

# Initialize variables
LOCATION=""
TEMPLATE_FILE_PATH=""
PARAMETERS_FILE_PATH=""
DEPLOYMENT_NAME=""
WHATIF=false


# Parse arguments
while [ "$#" -gt 0 ]; do
    case "$1" in
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --template-file)
            TEMPLATE_FILE_PATH="$2"
            shift 2
            ;;
        --parameters)
            PARAMETERS_FILE_PATH="$2"
            shift 2
            ;;
        -n|--name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        --what-if)
            WHATIF=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --location LOCATION --template-file PATH/TO/FILE --parameters PATH/TO/FILE [--name DEPLOYMENT NAME] [--what-if]"
            echo "       or: $0 -rg <resource group name> -l <Azure region> [--what-if] [--force]"
            echo "       --what-if: Perform a what-if deployment without making changes."
            echo "       --force: Force the creation of resources even if they already exist."
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
if [ -z "$LOCATION" ] || [ -z "TEMPLATE_FILE_PATH"] || [ -z "PARAMETERS_FILE_PATH"]; then
    echo "Error: --location, --template-file, and --parameters are required arguments."
    echo "Use --help for usage information."
    exit 1
fi

NAME_ARGUMENT=""
if [ -n "$DEPLOYMENT_NAME" ]; then
    NAME_ARGUMENT="--name $DEPLOYMENT_NAME"
fi

WHATIF_FLAG=""
if [ "$WHATIF" = true ]; then
    WHATIF_FLAG="--what-if"
fi

az deployment sub create --location "${LOCATION}" \
    --template-file "${TEMPLATE_FILE_PATH}" \
    --parameters "${PARAMETERS_FILE_PATH}" \
    --parameters oodServiceTreeId="0a914b56-486a-4979-b994-7b85132f8f0f"
    $NAME_ARGUMENT \
    $WHATIF_FLAG