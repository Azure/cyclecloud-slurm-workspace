
1. cp params/template/*.json params/
2. edit parameter files in params/
    * Note that we can convert these templates to .j2 files, I left that out for now.
    * all json files are ignored in params/ by .gitignore
3. Before deploying a hub:
    * bicep/hub/params/db_params.json adminPassword - the password for the mysql DB.
    * Optional: anf_params.json - we have a default of 4 TB right now.
    * Only base_spoke_params.json is outside the scope of this deployment.
    * `create_hub.sh --resource-group HUB_RG_NAME --location HUB_LOCATION`
    * See `create_hub.sh --help for more`
4. Before deploying a spoke:
    * bicep/hub/params/base_spoke_params.json adminPassword - CycleCloud hpcadmin password
    * bicep/hub/params/base_spoke_params.json adminSshPublicKey - hpcadmin public ssh key
    * `deploy_spoke.sh --hub-resource-group HUB_RG_NAME --spoke-number 1`
    * see `deploy_spoke.sh --help for more`
