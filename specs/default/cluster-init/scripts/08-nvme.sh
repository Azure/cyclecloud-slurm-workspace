#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

if is_compute; then
chmod +x $script_dir/../files/nvme_persistent_mount.sh
    $script_dir/../files/nvme_persistent_mount.sh xfs /mnt/nvme
fi
