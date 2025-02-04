# Azure CycleCloud Workspace for Slurm

Azure CycleCloud Workspace for Slurm is a new solution that simplifies and streamlines the creation and management of Slurm clusters on Azure. Azure CycleCloud Workspace for Slurm is an Azure marketplace solution template that allows users to easily create and configure pre-defined Slurm clusters with Azure CycleCloud without requiring any prior knowledge of the cloud or Slurm. Slurm clusters will be pre-configured with PMix v4, Pyxis, and enroot to support containerized AI Slurm jobs. Users can access the provisioned login node using SSH or Visual Studio Code to perform common tasks such as submitting and managing Slurm jobs.

Refer to [the Azure CycleCloud product documentation](https://learn.microsoft.com/azure/cyclecloud/overview-ccws) for more details.

Azure CycleCloud Workspace for Slurm will deploy the following resources in your Azure subscription as shown in the architecture below.
- a VNET and subnets to host CycleCloud, compute, Bastion and storage,
- a VM with CycleCloud pre-configured and a System Managed Identity with the proper roles assigned to create resources,
- a Network Security Group with rules defined and attached to the subnets,
- a storage account used by CycleCloud,
- (optionally) an Azure Bastion and its public IP,
- (optionally) a NAT Gateway and its public IP in order to provide outbound connectivity,
- (optionally) an Azure NetApp Files account, pool, and volume and its subnet,
- (optionally) an Azure Managed Filesystem and its subnet, and
- (optionally) a VNET Peering to a provided hub VNET


<img src="./images/architecture.png" width="100%">

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