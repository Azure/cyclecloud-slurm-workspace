#!/usr/bin/env python

import json
import os
import sys


def get_json_dict(file_name):
    file_path = os.path.join(os.getcwd(),file_name)
    with open(file_path, 'r') as file:
        content = file.read()
        data = json.loads(content)
    return data


def set_params(params, outputs):
    params['Region'] = outputs['location']['value']
    #params['Credentials']
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
    params['HTCImageName'] = outputs['partitions']['value']['htc']['image']
    params['HTCUseLowPrio'] = outputs['partitions']['value']['htc']['useSpot']

    #HPC
    params['HPCMachineType'] = outputs['partitions']['value']['hpc']['sku']
    params['MaxHPCExecuteNodeCount'] = int(outputs['partitions']['value']['hpc']['maxNodes'])
    params['HPCImageName'] = outputs['partitions']['value']['hpc']['image']

    #GPU
    params['GPUMachineType'] = outputs['partitions']['value']['gpu']['sku']
    params['MaxGPUExecuteNodeCount'] = int(outputs['partitions']['value']['gpu']['maxNodes'])
    params['GPUImageName'] = outputs['partitions']['value']['gpu']['image']

    #scheduler node
    #params['slurm'] #is this the slurm version??? no, so what is it?
    params['SchedulerMachineType'] = outputs['schedulerNode']['value']['sku']
    params['SchedulerImageName'] = outputs['schedulerNode']['value']['image']
    params['configuration_slurm_version'] = outputs['slurmSettings']['value']['version']
    # if outputs['slurmSettings']['value']['canUseSlurmHA']:
    #     params['configuration_slurm_ha_enabled'] = outputs['slurmSettings']['value']['slurmHA']
    params['configuration_slurm_accounting_enabled'] = False # outputs['slurmSettings']['value']['slurmAccounting']
    # if params['configuration_slurm_accounting_enabled']:
    #     params['configuration_slurm_accounting_user'] = outputs['ccswGlobalConfig']['value']['database_user']
    # if params['configuration_slurm_accounting_enabled']:
    #     params['configuration_slurm_accounting_password'] = outputs['slurmSettings']['value']['databaseAdminPassword']
    #params['configuration_slurm_accounting_url'] 
    #params['configuration_slurm_accounting_certificate_url']

    #login node(s)
    params['loginMachineType'] = (outputs['loginNodes']['value']['sku']).strip()
    params['NumberLoginNodes'] = int(outputs['loginNodes']['value']['initialNodes'])
    params['LoginImageName'] = outputs['loginNodes']['value']['image']
    params['EnableNodeHealthChecks'] = outputs['slurmSettings']['value']['healthCheckEnabled']

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

def main():
    slurm_params = get_json_dict('initial_params.json')
    ccsw_outputs = get_json_dict('ccswOutputs.json')
    set_params(slurm_params,ccsw_outputs)
    print(json.dumps(slurm_params,indent=4))

if __name__ == '__main__':
    main()