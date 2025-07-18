#!/bin/bash
set -e
RG=$1
LOCATION=$2
DCR_RG=$3

az deployment group create \
  --name "$RG-hub-mi" \
  --resource-group "$RG" \
  --template-file $(pwd)/hub-mi.bicep \
  --parameters dcrResourceGroup="${DCR_RG}" \