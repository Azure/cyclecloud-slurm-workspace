import argparse
import json
import os
import subprocess
import sys

"""
This is a simple development utility to override common settings when deploying
multiple slurm workspaces via sandbox UI parameters. This will also set the branch correctly.
Note that we use a -[letter] naming scheme for the resource groups. This is to ensure
we create a non-overlapping vnet. For example
my-rg-a -> 10.1.0.0/24
my-rg-b -> 10.2.0.0/24
...
my-rg-z -> 10.26.0.0/24
python3 deploy_sandbox_params.py -sandbox-ui-json raw-ui-parameters.json\
                                 --location southcentralus\
                                 --execute-vm-size Standard_F2s_v2\
                                 --cc-and-sched-vm-size Standard_F8s_v2\
                                 --resource-group my-rg-a
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("-j", "--sandbox-ui-json", required=True)
    parser.add_argument("-l", "--location", required=True)
    parser.add_argument("-r", "--resource-group", required=True)
    parser.add_argument("-e", "--execute-vm-size")
    parser.add_argument("-v", "--cc-and-sched-vm-size", dest="vm_size")
    parser.add_argument("--dry-run", action="store_true", default=False)


    args = parser.parse_args()
    if not args.resource_group[-2] == "-" and args.resource_group[-1].isalpha():
        print("Please add a sufix of -{single_letter}, i.e. ryhamelccsw-a")
        print("This suffix should be unique per running deployment, because we use it")
        print("to set the vnet's address space. i.e. -a 10.1.0.0/24, -b 10.2.0.0/24 and so on")
        sys.exit(1)

    branch =subprocess.check_output(['git', 'rev-parse', '--abbrev-ref', 'HEAD']).decode().strip()
    assert branch != "HEAD", "No headless checkouts allowed. If this is a tag, git checkout TAG -b TAG"

    ui_params = json.load(open(args.sandbox_ui_json))
    ui_params['branch'] = {'value': branch}
    ui_params["location"]["value"] = args.location
    ui_params["ccswConfig"]["value"]["location"] = args.location
    ui_params["ccswConfig"]["value"]["resource_group"] = args.resource_group

    suffix = args.resource_group.split("-")[-1][0]
    second_octal = ord(suffix) - ord("a") + 1
    ui_params["ccswConfig"]["value"]["network"]["vnet"]["address_space"] = f"10.{second_octal}.0.0/24"

    if args.vm_size:
        ui_params["ccVMSize"]["value"] = args.vm_size
        ui_params["ccswConfig"]["value"]["slurm_settings"]["scheduler_node"]["schedulerVMSize"] = args.vm_size
        ui_params["trash_for_arm_ttk"]["value"]["schedulerVMSize"] = args.vm_size

    if args.execute_vm_size:
        ui_params["ccswConfig"]["value"]["partition_settings"]["hpc"]["hpcVMSize"] = args.execute_vm_size
        ui_params["ccswConfig"]["value"]["partition_settings"]["htc"]["htcVMSize"] = args.execute_vm_size
        ui_params["ccswConfig"]["value"]["partition_settings"]["gpu"]["gpuVMSize"] = args.execute_vm_size
        ui_params["trash_for_arm_ttk"]["value"]["htcVMSize"] = args.execute_vm_size
        ui_params["trash_for_arm_ttk"]["value"]["hpcVMSize"] = args.execute_vm_size
        ui_params["trash_for_arm_ttk"]["value"]["gpuVMSize"] = args.execute_vm_size

    with open("util/testparam.json", "w") as fw:
        json.dump({
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        "contentVersion": "1.0.0.0",
        "parameters": ui_params
    }, fw, indent=2)

    cmd = f"az deployment sub create --location {args.location} --template-file ./bicep/mainTemplate.bicep --parameters util/testparam.json -n {args.resource_group}"
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