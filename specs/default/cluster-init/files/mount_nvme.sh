#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -b /dev/md12 ]; then
   mount /dev/md12 /mnt/nvme
else
   ${script_dir}/../scripts/08-nvme.sh
fi

