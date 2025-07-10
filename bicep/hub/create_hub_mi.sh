#!/bin/bash
set -e
RG=$1
LOCATION=$2

az deployment group create \
  --name "$RG-hub-mi" \
  --resource-group "$RG" \
  --template-file $(pwd)/hub-mi.bicep \