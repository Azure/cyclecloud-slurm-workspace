#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 
TOUCH_FILE=.10-fixes.done

# fix wrong NDv5 gpu count in gres.conf
function fix_ndv5()
{
    SLURM_AUTOSCALE_ROOT=/opt/azurehpc/slurm
    # Add an entry for Standard_ND96isr_H100_v5 if it doesn't exist
    if ! grep -q "Standard_ND96isr_H100_v5" $SLURM_AUTOSCALE_ROOT/autoscale.json; then
        logger -s "Add an entry for Standard_ND96isr_H100_v5 in autoscale.json"
        cp -f $SLURM_AUTOSCALE_ROOT/autoscale.json $SLURM_AUTOSCALE_ROOT/autoscale.json.orig
        jq '.default_resources = [{"select": {"node.vm_size": "Standard_ND96isr_H100_v5"}, "name": "slurm_gpus", "value": 8}] + .default_resources' $SLURM_AUTOSCALE_ROOT/autoscale.json.orig > $SLURM_AUTOSCALE_ROOT/autoscale.json

        touch $TOUCH_FILE
    fi
}

# remove space in between values in the device array https://github.com/Azure/cyclecloud-slurm/pull/291/files
function fix_generate_amd_devices()
{
    autoscale_version=$(jetpack config slurm.autoscale_version)
    if [[ $autoscale_version == "3.0.9" ]]; then
        logger -s "Fixing generate_amd_devices"
        PATCH_FILE=291.patch
        wget -q https://github.com/Azure/cyclecloud-slurm/pull/$PATCH_FILE -O $PATCH_FILE
        if [ ! -f $PATCH_FILE ]; then
            logger -s "Failed to download patch"
            return
        fi

        # Retrieve the python site packages to fix
        source /opt/azurehpc/slurm/venv/bin/activate
        PYTHON_MINOR_VERSION=$(python3 --version | cut -d '.' -f 2)

        # if the file to patch exists then apply the patch
        FILE_TO_PATCH=/opt/azurehpc/slurm/venv/lib/python3.$PYTHON_MINOR_VERSION/site-packages/slurmcc/cli.py
        if [ -f $FILE_TO_PATCH ]; then
            patch -t -p1 $FILE_TO_PATCH < $PATCH_FILE
            touch $TOUCH_FILE
        fi
    fi
}

if is_scheduler; then
    rm -f $TOUCH_FILE
    fix_ndv5
    fix_generate_amd_devices

    # We probably don't need to rerun the autoscaler at this time
    # # If touch file exists, then Update autoscaler
    # if [ -f $TOUCH_FILE ]; then
    #     logger -s "Update autoscaler"
    #     AZSLURM=$(which azslurm)
    #     $AZSLURM scale
    #     logger -s "Autoscaler updated"
    # fi
fi
