#!/usr/bin/env python

import json
import os 

def get_json_dict(file_name):
    file_path = os.path.join(os.getcwd(),file_name)
    with open(file_path, 'r') as file:
        content = file.read()
        data = json.loads(content)
    return data

def set_params(params,outputs):
    params['Region'] = outputs['ccswConfig']['value']['location']
    #params['Credentials']
    params['SubnetId'] = '/'.join([outputs['vnet']['value']['rg'],outputs['vnet']['value']['name'],outputs['ccswConfig']['value']['network']['vnet']['subnets']['computeSubnet'] ])
    
    #HTC
    params['HTCMachineType'] = outputs['ccswConfig']['value']['partition_settings']['htc']['htcVMSize']
    params['MaxHTCExecuteCoreCount'] = int(outputs['ccswConfig']['value']['partition_settings']['htc']['maxNodes'])
    params['HTCImageName'] = outputs['ccswConfig']['value']['partition_settings']['htc']['image']

    #HPC
    params['HPCMachineType'] = outputs['ccswConfig']['value']['partition_settings']['hpc']['hpcVMSize']
    params['MaxHPCExecuteCoreCount'] = int(outputs['ccswConfig']['value']['partition_settings']['hpc']['maxNodes'])
    params['HPCImageName'] = outputs['ccswConfig']['value']['partition_settings']['hpc']['image']

    #GPU
    params['GPUMachineType'] = outputs['ccswConfig']['value']['partition_settings']['gpu']['gpuVMSize']
    params['MaxGPUExecuteCoreCount'] = int(outputs['ccswConfig']['value']['partition_settings']['gpu']['maxNodes'])
    params['GPUImageName'] = outputs['ccswConfig']['value']['partition_settings']['gpu']['image']

    #scheduler node
    #params['slurm'] #is this the slurm version??? no, so what is it?
    params['SchedulerMachineType'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['schedulerVMSize']
    params['SchedulerImageName'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['schedulerImage']
    params['configuration_slurm_version'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['slurmVersion']
    if outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['canUseSlurmHA']:
        params['configuration_slurm_ha_enabled'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['slurmHA']
    params['configuration_slurm_accounting_enabled'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['slurmAccounting']
    if params['configuration_slurm_accounting_enabled']:
        params['configuration_slurm_accounting_user'] = outputs['ccswGlobalConfig']['value']['database_user']
    if params['configuration_slurm_accounting_enabled']:
        params['configuration_slurm_accounting_password'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['databaseAdminPassword']
    #params['configuration_slurm_accounting_url'] #TODO ask: is this the FDQN of the database???
    #params['configuration_slurm_accounting_certificate_url']

    #params['EnableNodeHealthChecks'] #todo ask: which node???

    #login node(s)
    params['loginMachineType'] = (outputs['ccswConfig']['value']['slurm_settings']['login_nodes']['loginVMSize']).strip()
    params['NumberLoginNodes'] = int(outputs['ccswConfig']['value']['slurm_settings']['login_nodes']['initialNodes'])
    
    #NFS
    params['NFSType'] = outputs['ccswConfig']['value']['filesystem']['shared']['config']['filertype']
    #FIX below: only works for NFS
    params['FilesystemSize'] = outputs['ccswConfig']['value']['filesystem']['shared']['config']['nfs_capacity_in_gb']
    params['UseBuiltinShared'] = False #TODO: change this to variable for external scenario 
    if params['NFSType'] == 'nfs':
        params['NFSAddress'] = outputs['ccswGlobalConfig']['value']['nfs_home_netad']
        params['NFSSharedExportPath'] = outputs['ccswGlobalConfig']['value']['nfs_home_path']
        params['NFSSharedMountOptions'] = outputs['ccswGlobalConfig']['value']['nfs_home_opts']
    
    #params['NFSAddress']
    #params['NFSSharedMountOptions']
    #params['NFSSharedExportPath']

    #params['AdditionalNFS']
    #params['NFSSchedType']
    #params['NFSSchedAddress']
    #params['NFSSchedMountOptions']
    #params['NFSSchedExportPath']
    #params['AdditionalNFSType']
    #params['AdditionalNFSExportPath']
    #params['AdditionalNFSMountOptions']
    #params['AdditionalNFSMountPoint']

def main():
    slurm_params = get_json_dict('initial_params.json')
    ccsw_outputs = get_json_dict('ccswOutputs.json')
    set_params(slurm_params,ccsw_outputs)
    print(json.dumps(slurm_params,indent=4))

if __name__ == '__main__':
    main()