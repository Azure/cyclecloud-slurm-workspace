# Azure CycleCloud Slurm Workspace

Azure CycleCloud Slurm Workspace is a new solution that simplifies and streamlines the creation and management of Slurm clusters on Azure. Azure CycleCloud Slurm Workspace is an Azure marketplace solution template that allows users to easily create and configure pre-defined Slurm clusters with Azure CycleCloud, without requiring any prior knowledge of the cloud or Slurm. Slurm clusters will be pre-configured with PMix v4, Pyxis and enroot to support containerized AI Slurm jobs. Users can access the provisioned login node using SSH or Visual Studio Code to perform common tasks like submitting and managing Slurm jobs.

## How to deploy ?
Search for **Slurm** in the Azure Marketplace and follow the steps to configure and deploy your Azure CycleCloud Slurm Workspace.
Once deployed, if needed, establish your connection between your local machine and the VNET hosting your environment. This can be already delivered by your corporate VPN, or a point to point VPN or through the Azure Bastion.
Connect to the CycleCloud web interface by browsing to https://<cycleccloud_ip>, and authenticate with the username and password provided during the deployment.
Confirm that both the Scheduler and the Login node are running.

## How to connect to the login node ?
When using the bastion, use one of the utility script __util/ssh_thru_bastion.sh__ or __util/tunnel_thru_bastion.sh__ to connect.
If not using a bastion, you have to establish the connectivity yourself.

## NSG Rules
If you bring your own VNET you will have to allow communication between subnets as defined in the [bicep/network-new.bicep](./bicep/network-new.bicep) file.

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.