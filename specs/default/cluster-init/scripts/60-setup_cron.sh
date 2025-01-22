#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

# configure the script to run on reboot
function setup_cron_onreboot()
{
    if ! [ -f /etc/crontab.orig ]; then
        cp /etc/crontab /etc/crontab.orig
        chmod +x ${CYCLECLOUD_SPEC_PATH}/files/run_on_reboot.sh
        echo "@reboot root ${CYCLECLOUD_SPEC_PATH}/files/run_on_reboot.sh" | tee -a /etc/crontab
    fi
}

if is_compute; then
    setup_cron_onreboot
fi

