#!/bin/bash
# This script is used to ssh into a VM through the bastion
# It assumes that the VM is in the same resource group as the bastion
# Retrieve the VM resource ID from the CycleCloud interface, in the VM properties

# It assumes that the user to connect to is hpcadmin and that the SSH Key is located in ~/.ssh/hpcadmin_id_rsa
resourceId=<vm_resource_id>
resourceGroup=$(echo $resourceId | cut -d'/' -f5)

az network bastion ssh --name bastion --resource-group $resourceGroup --target-resource-id $resourceId --auth-type ssh-key --username hpcadmin --ssh-key ~/.ssh/hpcadmin_id_rsa
