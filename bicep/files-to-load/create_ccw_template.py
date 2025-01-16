import argparse
import os
import subprocess

SINGLE_INDENT = ' ' * 4
DOUBLE_INDENT = ' ' * 8
CCW_TEMPLATE_NAME = 'Slurm-Workspace'

# Read in slurm project version and utility text files
def read_file(file_name):
    current_dir = os.getcwd()
    file_path = os.path.join(current_dir, file_name)
    with open(file_path, 'r') as file:
        return file.read()

# Vectorizes the version string into a tuple of integers
def parse_version(version): 
        return tuple([int(part) for part in version.split('.')])

AZSLURM_VERSION = read_file('cyclecloud-slurm-version.txt').strip()
AZSLURM_VERSION_PARSED = parse_version(AZSLURM_VERSION)

# Decorator for deprecating features based on the slurm project version
def deprecation_version(cutoff_version=None):
    def compare_slurm_versions(cutoff_version):
        cutoff_version_parsed = parse_version(cutoff_version)
        return AZSLURM_VERSION_PARSED < cutoff_version_parsed
    def decorator(func):
        def wrapper(template_file):
            if cutoff_version is None or compare_slurm_versions(cutoff_version):
                return func(template_file)
            else:
                return template_file
        wrapper.wrapped = func
        return wrapper
    return decorator

# Inserts insert_string into the the line above that of the first instance of substring in input_template
def insert_above(input_template, substring, insert_string):
    lines = input_template.split('\n')
    for i, line in enumerate(lines):
        if substring in line:
            lines.insert(i, insert_string)
            break
    return '\n'.join(lines)

# Inserts insert_string into the the line below that of the first instance of substring in input_template
def insert_below(input_template, substring, insert_string):
    lines = input_template.split('\n')
    for i, line in enumerate(lines):
        if substring in line:
            lines.insert(i + 1, insert_string)
            break
    return '\n'.join(lines)

# Deletes all lines between that of the first instance of start_substring (inclusive) and that of the first instance of end_substring (exclusive) in input_template
def remove_lines(input_template, start_substring, end_substring = None):
    lines = input_template.split('\n')
    start_index = None
    end_index = None
    delete_block = end_substring is not None

    for i, line in enumerate(lines):
        if start_substring in line and start_index is None:
            start_index = i
        elif start_index is not None: 
            if delete_block and end_substring in line:
                end_index = i
                break
            elif not delete_block: 
                # del lines[i]
                end_index = start_index+1
                break

    if start_index is not None and end_index is not None:
        del lines[start_index:end_index]
    
    return '\n'.join(lines)

# Deletes the line of the first instance of substring in input_template
def remove_line(input_template, substring):
    return remove_lines(input_template, substring)

# Replaces the first replace_count instances of lines containing substring in input_template with replacement_string
def replace_line(input_template, substring, replacement_string, replace_count = 1):
    lines = input_template.split('\n')
    for i, line in enumerate(lines):
        if replace_count == 0:
            break
        if substring in line:
            lines[i] = replacement_string
            replace_count -= 1
    return '\n'.join(lines)

# Apply all nested functions to the input_template
def apply_all_changes(input_template, funcs):
    def get_line_number(func):
        if hasattr(func,'wrapped'):
            return func.wrapped.__code__.co_firstlineno
        return func.__code__.co_firstlineno

    all_line_numbers = [get_line_number(func) for func in funcs]
    assert len(all_line_numbers) == len(set(all_line_numbers)), 'Multiple functions map to the same line. Please use the wrapped attribute for decorators.'
    sorted_funcs = sorted(funcs, key=get_line_number)
    for func in sorted_funcs:
        input_template = func(input_template)
    return input_template

# Write out CCW template 
def write_file(contents):
    current_dir = os.getcwd()
    file_path = os.path.join(current_dir, 'slurm-workspace.txt')
    with open(file_path, 'w') as file:
        file.write(contents)

def create_ccw_template(template_file):
    @deprecation_version()
    def rename_cluster(template_file):
        return template_file.replace('cluster Slurm', f'cluster {CCW_TEMPLATE_NAME}')
    @deprecation_version() # decorator omitted below as these changes to the main template would occur as a group
    def add_node_tags_parameter(template_file):
        def insert_node_tags_reference(template_file):
            return insert_below(template_file, 'Azure.Identities', SINGLE_INDENT + 'Tags = $NodeTags')

        def insert_parameter_node_tags(template_file):
            return insert_above(template_file, '[[parameters Auto-Scaling]]', read_file('util/parameter_NodeTags.txt'))
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])
    @deprecation_version()
    def update_slurm_configuration(template_file):
        @deprecation_version()
        def remove_slurm_packages(template_file):
            return remove_line(remove_line(template_file, 'slurm.install_pkg'), 'slurm.autoscale_pkg')

        @deprecation_version()
        def add_slurm_user_ids(template_file):
            slurm_user_ids = ['slurm.user.uid = 11100', 'slurm.user.gid = 11100', 'munge.user.uid = 11101', 'munge.user.gid = 11101']
            for user_id in slurm_user_ids[::-1]:
                template_file = insert_below(template_file, 'slurm.version', DOUBLE_INDENT + user_id)
            return template_file

        @deprecation_version()
        def remove_slurm_accounting_storageloc(template_file):
            return remove_line(template_file, 'slurm.accounting.storageloc')
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])
    @deprecation_version()
    def update_cluster_init_headers(template_file):
        def add_ccw_cluster_init(template_file):
            @deprecation_version()
            def relabel_cluster_init_headers(template_file):
                cluster_init_headers = ['cyclecloud/slurm:default', 'cyclecloud/slurm:scheduler', 'cyclecloud/slurm:login', 'cyclecloud/slurm:execute']
                aslurm_major_version = f'{AZSLURM_VERSION_PARSED[0]}.{AZSLURM_VERSION_PARSED[1]}.x'
                for cluster_init_header in cluster_init_headers:
                    template_file = replace_line(template_file, cluster_init_header, DOUBLE_INDENT + f'[[[cluster-init {cluster_init_header}:{aslurm_major_version}]]]')
                return template_file            
            template_file = remove_lines(template_file, 'cyclecloud/slurm:default','[[[')
            template_file = insert_below(template_file, 'cluster.identities.default', read_file('util/cluster_inits_slurm_ccw.txt'))
            template_file = relabel_cluster_init_headers(template_file)
            return template_file
        return add_ccw_cluster_init(template_file)
    @deprecation_version()
    def set_sched_to_persistent(template_file):
        return replace_line(template_file, 'Persistent = False', DOUBLE_INDENT + 'Persistent = True')
    @deprecation_version() # decorator omitted below as these changes to the main template would occur as a group
    def fix_execute_node_count_parameters(template_file):
        def fix_references_to_core_count_parameters(template_file):
            template_file = replace_line(template_file, '$MaxHPCExecuteCoreCount', SINGLE_INDENT + 'MaxCount = $MaxHPCExecuteNodeCount')
            template_file = replace_line(template_file, '$MaxHTCExecuteCoreCount', SINGLE_INDENT + 'MaxCount = $MaxHTCExecuteNodeCount')
            return template_file

        def remove_parameter_hpc_core_count(template_file):
            return remove_lines(template_file, '[[[parameter MaxHPCExecuteCoreCount]]]', '[[[')

        def remove_parameter_htc_core_count(template_file):
            return remove_lines(template_file, '[[[parameter MaxHTCExecuteCoreCount]]]', '[[[')

        def add_parameters_execute_node_counts(template_file):
            return insert_above(template_file, '[[[parameter MaxDynamicExecuteCoreCount]]]', read_file('util/parameters_MaxExecuteNodeCounts.txt'))
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])
    @deprecation_version() # decorator omitted below as these changes to the main template would occur as a group
    def add_gpu_nodearray_and_parameters(template_file):
        def insert_nodearray_gpu(template_file):
            return insert_above(template_file, '[[nodearray htc]]', read_file('util/nodearray_gpu.txt'))

        def insert_parameter_gpu_machine_type(template_file):
            return insert_above(template_file, '[[[parameter DynamicMachineType]]]', read_file('util/parameter_GPUMachineType.txt'))

        def insert_parameter_gpu_image_name(template_file): 
            return insert_above(template_file, '[[[parameter DynamicImageName]]]', read_file('util/parameter_GPUImageName.txt'))

        def insert_parameter_gpu_use_low_prio(template_file): 
            return insert_above(template_file, '[[[parameter DynamicUseLowPrio]]]', read_file('util/parameter_GPUUseLowPrio.txt'))

        def insert_parameter_gpu_spot_max_price(template_file): 
            return insert_above(template_file, '[[[parameter DynamicUseLowPrio]]]', read_file('util/parameter_GPUSpotMaxPrice.txt'))

        def insert_parameter_gpu_cluster_init_specs(template_file):
            return insert_above(template_file, '[[[parameter DynamicClusterInitSpecs]]]', read_file('util/parameter_GPUClusterInitSpecs.txt'))
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])
    @deprecation_version() # decorator omitted below as these changes to the main template would occur as a group
    def update_login_nodearray_and_add_parameters(template_file):
        def fix_nodearray_login_image_name(template_file):
            end_marker = 'cluster-init cyclecloud/slurm:login'
            template_file = remove_lines(template_file, '[[nodearray login]]', end_marker)
            template_file = insert_above(template_file, end_marker, read_file('util/nodearray_login.txt'))
            return template_file

        def insert_parameter_login_image_name(template_file): 
            return insert_above(template_file, '[[[parameter HPCImageName]]]', read_file('util/parameter_LoginImageName.txt'))

        def insert_parameter_login_cluster_init_specs(template_file):
            return insert_above(template_file, '[[[parameter HTCClusterInitSpecs]]]', read_file('util/parameter_LoginClusterInitSpecs.txt'))
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])
    # Update network attached storage (NAS)-related UI text
    @deprecation_version()
    def update_nas_gui(template_file):
        def fix_disk_warnings(template_file):
            return replace_line(template_file,
                                'switching an active cluster over to NFS or Lustre from Builtin will delete the shared disk',
                                DOUBLE_INDENT + 'Config.Template := "<p><b>Warning</b>: switching an active cluster over to NFS from Builtin will delete the shared disk.</p>"',
                                replace_count = 2)

        # replace_count = 2 because AML is not an accepted option for /sched and /shared, i.e., where this text appears in the original template.
        def fix_nfs_address(template_file):
            return replace_line(template_file,
                                'The IP address or hostname of the NFS server or Lustre FS',
                                DOUBLE_INDENT + 'Description = The IP address or hostname of the NFS server. Also accepts a list comma-separated addresses, for example, to mount a frontend load-balanced Azure HPC Cache.',
                                replace_count = 2)

        # replace_count = 2 because AML is an acceptable option for parameter AdditionalNFSType but not /sched and /shared, i.e., the first two NFS defined in the original template.
        def fix_nfs_type_options(template_file):
            return replace_line(template_file,
                                '[Label="Azure Managed Lustre"',
                                DOUBLE_INDENT + 'Config.Entries := {[Label="External NFS"; Value="nfs"]}',
                                replace_count = 2)
        return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)]) 
    return apply_all_changes(template_file, [func for _, func in locals().items() if callable(func)])  

def main():
    parser = argparse.ArgumentParser(description='Generate the CycleCloud Workspace for Slurm template')
    parser.add_argument("--validate",
                        dest="run_validation",
                        default=False,
                        action="store_true",
                        help="Check template generated by this file against what\'s stored on disk")
    validate = parser.parse_args().run_validation

    template_uri = f'https://raw.githubusercontent.com/Azure/cyclecloud-slurm/refs/tags/{AZSLURM_VERSION}/templates/slurm.txt'
    azslurm_template = subprocess.check_output(['curl', '-s', template_uri]).decode('utf-8')
    ccw_template = create_ccw_template(azslurm_template)
    if validate:
        if ccw_template != read_file('slurm-workspace.txt'):
            print(ccw_template)
            raise Exception('Please compare the template present on disk with the template generated by this file and update slurm-workspace.txt.')
    else:
        write_file(ccw_template)    

if __name__ == '__main__':
    main()