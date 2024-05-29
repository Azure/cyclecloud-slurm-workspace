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
    params['MaxHTCExecuteNodeCount'] = int(outputs['ccswConfig']['value']['partition_settings']['htc']['maxNodes'])
    params['HTCImageName'] = outputs['ccswConfig']['value']['partition_settings']['htc']['image']
    params['HTCUseLowPrio'] = outputs['ccswConfig']['value']['partition_settings']['htc']['use_spot']

    #HPC
    params['HPCMachineType'] = outputs['ccswConfig']['value']['partition_settings']['hpc']['hpcVMSize']
    params['MaxHPCExecuteNodeCount'] = int(outputs['ccswConfig']['value']['partition_settings']['hpc']['maxNodes'])
    params['HPCImageName'] = outputs['ccswConfig']['value']['partition_settings']['hpc']['image']

    #GPU
    params['GPUMachineType'] = outputs['ccswConfig']['value']['partition_settings']['gpu']['gpuVMSize']
    params['MaxGPUExecuteNodeCount'] = int(outputs['ccswConfig']['value']['partition_settings']['gpu']['maxNodes'])
    params['GPUImageName'] = outputs['ccswConfig']['value']['partition_settings']['gpu']['image']

    #scheduler node
    #params['slurm'] #is this the slurm version??? no, so what is it?
    params['SchedulerMachineType'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['schedulerVMSize']
    params['SchedulerImageName'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['schedulerImage']
    params['configuration_slurm_version'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['slurmVersion']
    # if outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['canUseSlurmHA']:
    #     params['configuration_slurm_ha_enabled'] = outputs['ccswConfig']['value']['slurm_settings']['scheduler_node']['slurmHA']
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
    params['LoginImageName'] = outputs['ccswConfig']['value']['slurm_settings']['login_nodes']['loginImage']
    params['EnableNodeHealthChecks'] = outputs['ccswConfig']['value']['slurm_settings']['health_check']

    #Network Attached Storage
    params['UseBuiltinShared'] = outputs['filer_info_final']['value']['home']['create_new'] and (outputs['filer_info_final']['value']['home']['filertype'] == 'nfs')
    if params['UseBuiltinShared']:
        params['FilesystemSize'] = outputs['filer_info_final']['value']['home']['nfs_capacity_in_gb']
    else:
        params['NFSType'] = 'nfs' if outputs['filer_info_final']['value']['home']['filertype'] in ['nfs','anf'] else 'lustre'
        # We no longer need to handle these differently based on the fs type, as each
        # fs module's common outputs map to these.
        params['NFSSharedExportPath'] = outputs['filer_info_final']['value']['home']['export_path']
        params['NFSSharedMountOptions'] = outputs['filer_info_final']['value']['home']['mount_options']
        params['NFSAddress'] = outputs['filer_info_final']['value']['home']['ip_address']

    params['AdditionalNFS'] = outputs['filer_info_final']['value']['additional']['use']
    if params['AdditionalNFS']:
        params['AdditionalNFSType'] = 'nfs' if outputs['filer_info_final']['value']['additional']['filertype'] in ['nfs','anf'] else 'lustre'
        params['AdditionalNFSMountPoint'] = outputs['filer_info_final']['value']['additional']['mount_path']
        params['AdditionalNFSExportPath'] = outputs['filer_info_final']['value']['additional']['export_path']
        params['AdditionalNFSMountOptions'] = outputs['filer_info_final']['value']['additional']['mount_options']
        params['AdditionalNFSAddress'] = outputs['filer_info_final']['value']['additional']['ip_address']

def main():
    slurm_params = get_json_dict('initial_params.json')
    ccsw_outputs = get_json_dict('ccswOutputs.json')
    set_params(slurm_params,ccsw_outputs)
    print(json.dumps(slurm_params,indent=4))

if __name__ == '__main__':
    main()