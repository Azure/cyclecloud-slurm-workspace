import argparse
import json
import os
import subprocess
import sys

"""
This is a simple development utility to override common settings when deploying
multiple workspaces for Slurm via sandbox UI parameters. This will also set the branch correctly.

python3 deploy_sandbox_params.py --sandbox-ui-json raw-ui-parameters.json\
                                 --location southcentralus\
                                 --execute-vm-size Standard_F2s_v2\
                                 --cc-and-sched-vm-size Standard_F8s_v2\
                                 --resource-group my-rg-a
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("-j", "--sandbox-ui-json", required=True)
    parser.add_argument("-l", "--location")
    parser.add_argument("-r", "--resource-group")
    parser.add_argument("-e", "--execute-vm-size")
    parser.add_argument("-v", "--cc-and-sched-vm-size", dest="vm_size")
    parser.add_argument("--dry-run", action="store_true", default=False)
    parser.add_argument("-b", "--branch")
    parser.add_argument("-i", "--insiders", action="store_true", default=False)
    parser.add_argument("-s", "--vnet-address-space")

    args = parser.parse_args()

    ui_params = json.load(open(args.sandbox_ui_json))

    if args.resource_group:
        ui_params["resourceGroup"]["value"] = args.resource_group

    if args.vnet_address_space:
        ui_params["network"]["value"]["addressSpace"] = args.vnet_address_space

    if args.branch:
        branch = args.branch
    else:
        branch = subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', 'HEAD']).decode().strip()
        assert branch != "HEAD", "No headless checkouts allowed. If this is a tag, git checkout TAG -b TAG"
        pushed_branches = subprocess.check_output(['git', 'branch', '-la']).decode().split()
        if f'remotes/origin/{branch}' not in pushed_branches:
            print(f"{branch} has not been pushed yet. Either push this branch, or pass in --branch main")
            return

    ui_params['branch'] = {'value': branch}
    if 'insidersBuild' in ui_params:
        if args.insiders:
            ui_params['insidersBuild']["value"] = args.insiders
    else:
        ui_params['insidersBuild'] = {'value': args.insiders}

    if args.location:
        ui_params["location"]["value"] = args.location

    if args.vm_size:
        ui_params["ccVMSize"]["value"] = args.vm_size
        ui_params["schedulerNode"]["value"]["sku"] = args.vm_size

    if args.execute_vm_size:
        ui_params["hpc"]["value"]["sku"] = args.execute_vm_size
        ui_params["htc"]["value"]["sku"] = args.execute_vm_size
        ui_params["gpu"]["value"]["sku"] = args.execute_vm_size

    with open("util/testparam.json", "w") as fw:
        json.dump({
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        "contentVersion": "1.0.0.0",
        "parameters": ui_params
    }, fw, indent=2)

    resource_group = ui_params["resourceGroup"]["value"]
    location = ui_params["location"]["value"]
    cmd = f"az deployment sub create --location {location} --template-file ./bicep/mainTemplate.bicep --parameters util/testparam.json -n {resource_group}"
    if args.dry_run:
        print("DRY RUN")
        print(cmd)
        return
    os.system(cmd)


if __name__ == "__main__":
    if not os.path.exists("bicep/install.sh"):
        print("Please run this from the root of the project")
        sys.exit(1)
    main()