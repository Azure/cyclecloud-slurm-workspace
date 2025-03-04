#!/usr/bin/env python

import argparse
import hashlib
import json
import os
import shutil
from subprocess import check_output
import sys
import typing


def get_json_dict(file_name):
    abs_path = os.path.abspath(file_name)
    with open(abs_path) as fr:
        return json.load(fr)


def set_slurm_params(params, dbPassword, outputs):
    params['Region'] = outputs['location']['value']
    if outputs['vnet']['value']['type'] == 'new':
        subnetID = outputs['vnet']['value']['computeSubnetId']
        subnet_toks = subnetID.split("/")
        if len(subnet_toks) >= 11:
            params['SubnetId'] = "/".join([subnet_toks[4], subnet_toks[8], subnet_toks[10]])
        else:
            print(f"Unexpected subnet id {subnetID} - passing as SubnetId directly instead of resource_group/vnet_name/subnet_name", file=sys.stderr)
            params['SubnetId'] = subnetID
    else:
        params['SubnetId'] = '/'.join([outputs['vnet']['value']['rg'], outputs['vnet']['value']['name'], outputs['vnet']['value']['computeSubnetName']])
        
    #HTC
    params['HTCMachineType'] = outputs['partitions']['value']['htc']['sku']
    params['MaxHTCExecuteNodeCount'] = int(outputs['partitions']['value']['htc']['maxNodes'])
    params['HTCImageName'] = outputs['partitions']['value']['htc']['osImage']
    params['HTCUseLowPrio'] = outputs['partitions']['value']['htc']['useSpot']

    #HPC
    params['HPCMachineType'] = outputs['partitions']['value']['hpc']['sku']
    params['MaxHPCExecuteNodeCount'] = int(outputs['partitions']['value']['hpc']['maxNodes'])
    params['HPCImageName'] = outputs['partitions']['value']['hpc']['osImage']

    #GPU
    params['GPUMachineType'] = outputs['partitions']['value']['gpu']['sku']
    params['MaxGPUExecuteNodeCount'] = int(outputs['partitions']['value']['gpu']['maxNodes'])
    params['GPUImageName'] = outputs['partitions']['value']['gpu']['osImage']

    #scheduler node
    #params['slurm'] #is this the slurm version??? no, so what is it?
    params['SchedulerMachineType'] = outputs['schedulerNode']['value']['sku']
    params['SchedulerImageName'] = outputs['schedulerNode']['value']['osImage']
    params['configuration_slurm_version'] = outputs['slurmSettings']['value']['version']
    # if outputs['slurmSettings']['value']['canUseSlurmHA']:
    #     params['configuration_slurm_ha_enabled'] = outputs['slurmSettings']['value']['slurmHA']
    params['configuration_slurm_accounting_enabled'] = bool(outputs['databaseInfo']['value'])
    if params['configuration_slurm_accounting_enabled']:
        params['configuration_slurm_accounting_user'] = outputs['databaseInfo']['value']['databaseUser']
    if params['configuration_slurm_accounting_enabled']:
        params['configuration_slurm_accounting_password'] = dbPassword
    if params['configuration_slurm_accounting_enabled']:
        params['configuration_slurm_accounting_url'] = outputs['databaseInfo']['value']['url']
    #params['configuration_slurm_accounting_certificate_url']

    #login node(s)
    params['loginMachineType'] = (outputs['loginNodes']['value']['sku']).strip()
    params['NumberLoginNodes'] = int(outputs['loginNodes']['value']['initialNodes'])
    params['LoginImageName'] = outputs['loginNodes']['value']['osImage']
    params['EnableNodeHealthChecks'] = outputs['slurmSettings']['value']['healthCheckEnabled']

    #Execute node tags
    params['NodeTags'] = outputs['nodeArrayTags']['value']

    #Network Attached Storage
    params['UseBuiltinShared'] = outputs['filerInfoFinal']['value']['home']['type'] == 'nfs-new' 
    if params['UseBuiltinShared']:
        params['FilesystemSize'] = outputs['filerInfoFinal']['value']['home']['nfsCapacityInGb']
    else:
        params['NFSType'] = 'nfs' if outputs['filerInfoFinal']['value']['home']['type'] in ['nfs-existing','anf-new'] else 'lustre'
        # We no longer need to handle these differently based on the fs type, as each
        # fs module's common outputs map to these.
        params['NFSSharedExportPath'] = outputs['filerInfoFinal']['value']['home']['exportPath']
        params['NFSSharedMountOptions'] = outputs['filerInfoFinal']['value']['home']['mountOptions']
        params['NFSAddress'] = outputs['filerInfoFinal']['value']['home']['ipAddress']

    params['AdditionalNFS'] = outputs['filerInfoFinal']['value']['additional']['type'] != 'disabled'
    if params['AdditionalNFS']:
        params['AdditionalNFSType'] = 'nfs' if outputs['filerInfoFinal']['value']['additional']['type'] in ['nfs-existing','anf-new'] else 'lustre'
        params['AdditionalNFSMountPoint'] = outputs['filerInfoFinal']['value']['additional']['mountPath']
        params['AdditionalNFSExportPath'] = outputs['filerInfoFinal']['value']['additional']['exportPath']
        params['AdditionalNFSMountOptions'] = outputs['filerInfoFinal']['value']['additional']['mountOptions']
        params['AdditionalNFSAddress'] = outputs['filerInfoFinal']['value']['additional']['ipAddress']


def set_ood_params(params, outputs):
    slurm_params = get_json_dict('initial_params.json')
    # We want to essentially inherit certain settings from the slurm cluster.
    set_slurm_params(slurm_params, "", outputs)
    params['NFSAddress'] = slurm_params.get('NFSAddress') or 'ccw-scheduler'
    params['NFSSharedExportPath'] = slurm_params.get('NFSSharedExportPath') or '/shared'
    params['NFSSharedMountOptions'] = slurm_params.get('NFSSharedMountOptions')
    params['SubnetId'] = slurm_params["SubnetId"]
    params['Region'] = slurm_params['Region']
    params['Credentials'] = slurm_params['Credentials']

    params['MachineType'] = outputs['ood']['value'].get('sku')
    params['ManagedIdentity'] = outputs['ood']['value'].get('managedIdentity')
    params['BootDiskSize'] = outputs['ood']['value'].get('BootDiskSize')
    params['ImageName'] = outputs['ood']['value'].get('osImage')

    params['ood_server_name'] = outputs['ood']['value'].get('fqdn','')
    params['ood_entra_user_map_match'] = outputs['ood']['value'].get('userDomain')
    params['ood_entra_client_id'] = outputs['ood']['value'].get('clientId')
    params['ood_entra_tenant_id'] = outputs['ood']['value'].get('tenantId')
    params['ood_nic'] = outputs['ood']['value'].get('nic')

class ClusterInitSpec:
    def __init__(self, project: str, version: str, spec: str, targets: typing.List[str]):
        self.project = project
        self.version = version
        self.spec = spec
        self.targets = targets
        self.cluster_init_key = f"{self.project}:{self.spec}:{self.version}"


def download_cluster_init(outputs, root_folder, locker) -> typing.List[ClusterInitSpec]:
    ret = []
    for record in (outputs['clusterInitSpecs'].get("value") or []):
        url = _strip_tags_from_github_url(record)
        url_hash = hashlib.sha256(url.encode())
        
        folder = os.path.join(root_folder, url_hash.hexdigest())
        if not os.path.exists(folder):
            # download and move to avoid repeated failures with partial downloads/uploads
            check_output(["/usr/local/bin/cyclecloud", "project", "fetch", url, folder + ".tmp"])
            check_output(["/usr/local/bin/cyclecloud", "project", "upload", locker], cwd=folder + ".tmp")
            shutil.move(folder + ".tmp", folder)
            with open(os.path.join(folder, "download-url"), "w") as fw:
                fw.write(url)
        proj_info_raw = check_output(["/usr/local/bin/cyclecloud", "project", "info"], cwd=folder).decode()
        proj_info = {}
        for line in proj_info_raw.splitlines():
            key, rest = line.split(":", 1)
            proj_info[key.lower()] = rest.strip()
        ret.append(ClusterInitSpec(proj_info["name"],
                                   proj_info["version"],
                                   record.get("spec") or "default",
                                   record["target"]))
    return ret


def _strip_tags_from_github_url(record):
    url = record["gitHubReleaseURL"]
    if "/tag/" in url:
        return url.replace("/tag", "")
    return url


def _version_from_url(record):
    if record.get("version"):
        return record["version"]
    return record["gitHubReleaseURL"].split("/")[-1]


def set_cluster_init_params(params: dict, specs: typing.List[ClusterInitSpec], cluster_name: str, target_params: dict) -> None:
    order = 10000
    for spec in specs:
        for target in spec.targets:
            target_key = f"{target_params[target.lower()]}"
            if not params.get(target_key):
                params[target_key] = {}

            params[target_key][spec.cluster_init_key] = {
                "Order": order,
                "Spec": spec.spec,
                "Name": spec.cluster_init_key,
                "Project": spec.project,
                "Locker": "azure-storage",
                "Version": spec.version
            }
            order += 100


def main():
    parser = argparse.ArgumentParser(description="TODO RDH")
    parser.add_argument("--locker", default="azure-storage")
    parser.add_argument("--cluster-init-working-dir", default="cluster-init")
    subparsers = parser.add_subparsers()
    ccw_parser = subparsers.add_parser("slurm")
    # TODO this needs to be by cluster type
    target_params = {
        "login": "LoginClusterInitSpecs",
        "gpu": "GPUClusterInitSpecs",
        "hpc": "HPCClusterInitSpecs",
        "htc": "HTCClusterInitSpecs",
        "scheduler": "SchedulerClusterInitSpecs",
        "dynamic": "DynamicClusterInitSpecs",
        "ood": "ClusterInitSpecs"
    }
    ccw_parser.set_defaults(cluster_type="slurm", target_params=target_params)
    ccw_parser.add_argument("--dbPassword", dest="dbPassword", default="", help="MySQL database password")
    
    ood_parser = subparsers.add_parser("ood")
    ood_parser.set_defaults(cluster_type="ood", target_params=target_params)
    
    args = parser.parse_args()

    if args.cluster_type == "slurm":
        output_params = get_json_dict('initial_params.json')
    else:
        output_params = {}
    ccw_outputs = get_json_dict('ccwOutputs.json')

    specs = download_cluster_init(ccw_outputs, os.path.join(os.getcwd(), args.cluster_init_working_dir), args.locker)
    set_cluster_init_params(output_params, specs, args.cluster_type, args.target_params)
    if args.cluster_type == "slurm":
        set_slurm_params(output_params, args.dbPassword, ccw_outputs)
    else:
        set_ood_params(output_params, ccw_outputs)
    print(json.dumps(output_params, indent=4))


if __name__ == '__main__':
    main()