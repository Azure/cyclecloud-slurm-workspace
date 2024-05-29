#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

# fix wrong NDv5 gpu count in gres.conf
function fix_ndv5()
{
    SLURM_AUTOSCALE_ROOT=/opt/azurehpc/slurm
    # Add an entry for Standard_ND96isr_H100_v5 if it doesn't exist
    if ! grep -q "Standard_ND96isr_H100_v5" $SLURM_AUTOSCALE_ROOT/autoscale.json; then
        logger -s "Add an entry for Standard_ND96isr_H100_v5 in autoscale.json"
        cp -f $SLURM_AUTOSCALE_ROOT/autoscale.json $SLURM_AUTOSCALE_ROOT/autoscale.json.orig
        jq '.default_resources = [{"select": {"node.vm_size": "Standard_ND96isr_H100_v5"}, "name": "slurm_gpus", "value": 8}] + .default_resources' $SLURM_AUTOSCALE_ROOT/autoscale.json.orig > $SLURM_AUTOSCALE_ROOT/autoscale.json

        # Update autoscaler
        logger -s "Update autoscaler"
        /root/bin/azslurm scale
        logger -s "Autoscaler updated"
    fi

}

if is_scheduler; then
    fix_ndv5
fi
