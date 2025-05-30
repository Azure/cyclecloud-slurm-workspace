#!/bin/bash
# TODO just documenting exactly the command I ran
az deployment group create --name bfl-hub-test-vpn --resource-group bfl-hub-test --template-file vpn_gateway.bicep
