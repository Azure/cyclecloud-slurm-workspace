
0. Login to azure via the az cli, as well as enabling the graph api.
    * az login
        * Make sure the correct subscription is selected.
    * az login --scope https://graph.microsoft.com//.default
0. Create the cyclecloud-slurm-workspace directory for deploying the hub and spoke
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
5. Create a spoke: i.e. a CycleCloud + Slurm cluster deployment:
    * `bicep/hub/params/base_spoke_params.json` Update `adminPassword` - CycleCloud hpcadmin password
    * `bicep/hub/params/base_spoke_params.json` Update `adminSshPublicKey` - hpcadmin public ssh key
    * `deploy_spoke.sh --hub-resource-group HUB_RG_NAME --spoke-number 1`