# Partially automated app registration for Azure CycleCloud Workspace for Slurm

Note: These instructions are only for CycleCloud developers at this time. There will be a final version intended for end-users available in the official Azure CycleCloud Workspace for Slurm documentation following the release of Azure CycleCloud 8.8.0. 

## Pre-deployment 

Follow the below steps to create a Microsoft Entra ID application registration **before** deploying Azure CycleCloud Workspace for Slurm if one needed. Please check with your organization to ensure that there does not already exist an application registration available for use.

This script will also create a new user-assigned managed identity resource for exclusive use with the application registration.

Download the script with the following sequence of commands:

```
LATEST_RELEASE=$(curl -sSL -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/Azure/cyclecloud-slurm-workspace/releases/latest" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p')
wget "https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/refs/tags/${LATEST_RELEASE}/util/entra_predeploy.sh"
```

Replace the values for ```LOCATION```,```ENTRA_MI_RESOURCE_GROUP```, ```MI_NAME```, and ```APP_NAME``` in the downloaded script, including the characters ```<``` and ```>``` with your preferred text editor.

- ```LOCATION``` is the Azure region in which to create the managed identity resource and its resource group.
- ```ENTRA_MI_RESOURCE_GROUP``` is the name of the resource group containing the managed identity resource. 
- ```MI_NAME``` is the desired name of the managed identity resource. It may not contain spaces.
- ```APP_NAME``` is the designed name of the Microsoft Entra ID application registration. 

Finally, run the script: 

```
sh entra_predeploy.sh
```


Make note of the Tenant, Client, and Managed Identity Resource IDs. 

## Deployment

Navigate to the preview of the official Azure CycleCloud Workspace for Slurm offer in the Azure Marketplace under private plans. It is labeled "**Azure CycleCloud Workspace for Slurm (preview)**." Do not go the preview of the separate preview offer named "Azure CycleCloud Workspace for Slurm Preview (preview)." We are aware that this naming convention is confusing. 

1. Click the blue "Create" button. 
2. Check off "Enable Microsoft Entra ID SSO" at the bottom of the Basics menu, select the managed identity created in the previous section, and enter the Tenant and Client IDs noted in the last section. 
3. Proceed through the remainder of the workflow. 

## Post-deployment

Recent changes to Microsoft's internal policies have hamstrung our ability to update application registrations via the az CLI. We will therefore need to manually update the redirect URIs in the Microsoft Entra ID application registration. 

Following the successful deployment of Azure CycleCloud Workspace for Slurm, navigate to the deployment's resource group and make note of the following values:

- The private IP address of the CycleCloud VM
- The private IP address of the Open OnDemand NIC if you chose to deploy OpenOnDemand (begins with "ood-" and ends with "-nic")

Next, navigate to the Microsoft Entra ID application registration intended for use with Azure CycleCloud Workspace for Slurm. Expand the menu under "Manage" on the left-hand side of the Azure Portal and then click on "Authentication." 

### Using the registration created with the pre-deployment instructions

Find the page section labeled "Single-page application Redirect URIs" and replace ```CYCLECLOUD_VM_IP.PLACEHOLDER``` in the listed URIs with the private IP address of the CycleCloud VM. Do not replace the entire URI. 

If you deployed Open OnDemand, then find the page section labeled "Single-page application Redirect URIs" and replace ```OPEN_ONDEMAND_NIC_IP.PLACEHOLDER``` in the listed URI with the private IP address of the Open OnDemand NIC. Do not replace the entire URI. 

### Using your own application registration

In the below text: 

- ```XX.XX.XX.XX``` refers to the private IP address of the CycleCloud VM
- ```ZZ.ZZ.ZZ.ZZ``` refers to the private IP address of the Open OnDemand NIC 

You will need to add ```https://XX.XX.XX.XX/home``` and, if you deployed Open OnDemand ```https://XX.XX.XX.XX/login``` to the list of single-page application redirect URIs and ```https://ZZ.ZZ.ZZ.ZZ/oidc``` to the list of web redirect URIs. 

This can be done by finding the "Platform Configurations" section, selecting "Add a platform," and navigating to the proper submenu (e.g., "Single-page application" for the single-page application URIs).

Click "Save" at the bottom of the page. You should now be able to log into the CycleCloud virtual machine using Microsoft Entra ID authentication. 