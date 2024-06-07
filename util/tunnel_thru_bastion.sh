#!/bin/bash
# This script is used to establish an ssh tunnel using through the bastion
# It assumes that the VM establishing the tunnel is in the same resource group as the bastion
# Retrieve the VM resource ID from the CycleCloud interface, in the VM properties

resourceId=<vm_resource_id>
resourceGroup=$(echo $resourceId | cut -d'/' -f5)

az network bastion tunnel --name bastion --resource-group $resourceGroup --target-resource-id $resourceId --resource-port 22 --port 8822
