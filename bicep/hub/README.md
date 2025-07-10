
0. Login to azure via the az cli, as well as enabling the graph api.
    * az login
        * Make sure the correct subscription is selected.
    * az login --scope https://graph.microsoft.com//.default
1. Create the cyclecloud-slurm-workspace directory for deploying the hub and spoke
    ```bash
        git clone -b abatallas/gb200_hub_spoke https://github.com/Azure/cyclecloud-slurm-workspace.git
        cd cyclecloud-slurm-workspace/bicep/hub
        cp params/template/*.json params/
    ```
2. Edit hub parameter json files found within cyclecloud-slurm-workspace/bicep/hub/params/
    * In `params/db_params.json` update `adminPassword` - the password for the mysql DB.
    * Optional: `params/anf_params.json` - we have a default `sizeTiB` of 4 TB right now.
    * The rest of the parameter files likely do not need to be changed.
    * **Note***: `base_spoke_params.json` is only used when deploying a spoke, it goes unused by create_hub.sh
3. Create the hub deployments
    * Pick a resource group name and location, then run the following: **Note** we will create the resource group if it does not exist.
    * `create_hub.sh --resource-group HUB_RG_NAME --location HUB_LOCATION`
4. Add a VPN Gateway to the hub resource group using the Azure Portal.
5. Follow steps below for "How to create a private endpoint for storage account resources"
6. Create a spoke: i.e. a CycleCloud + Slurm cluster deployment:
    * `bicep/hub/params/base_spoke_params.json` Update `adminPassword` - CycleCloud hpcadmin password
    * `bicep/hub/params/base_spoke_params.json` Update `adminSshPublicKey` - hpcadmin public ssh key
    * `bicep/hub/params/base_spoke_params.json` Update storagePrivateDnsZone.id with the resource ID of the private DNS zone created in step 5.
    * `deploy_spoke.sh --hub-resource-group HUB_RG_NAME --spoke-number 1`
7. Once the spoke finishes, perform the following to install the latest version of CycleCloud8. **Assuming the CC vm is at 10.1.0.4**
    ```bash
    scp cyclecloud8.rpm hpcadmin@10.1.0.4:~/
    ssh hpcadmin@10.1.0.4
    sudo -i
    cd /opt/ccw
    bash install.sh --local-package ~hpcadmin/cyclecloud8.rpm
    ```

## How to create a private endpoint for storage account resources
1. Create a new private endpoint resource in the hub resource group via the Azure Portal. Complete this once for each storage account. Set the following under the named menu tab: 
    * Resource
        * Connection Method: Connect to an Azure resource in my directory
        * Resource type: `Microsoft.Storage/storageAccounts`
        * Resource: *Name of storage account*
        * Target sub-resource: `blob`
    * Virtual Network: 
        * Virtual network: *Name of hub virtual network*
        * Subnet: `default`
    * DNS:
        * Integrate with private DNS zone: `Yes`
        * Subscription: *Subscription in which the hub is deployed*
        * Resource group: *Resource group in which the hub is deployed*
2. Navigate to the private DNS zone resource named `privatelink.blob.core.windows.net` in the hub resource group. 
    * Expand the **DNS Management** sub-menu in the left-hand side menu and select *Virtual Network Links*
    * Click **Add**
    * Choose an arbitary name for the link, select the hub vnet in the relevant dropdown menu, and click *Create*. No modifications to the *Configuration* section are required. 