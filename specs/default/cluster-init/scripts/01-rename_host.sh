#!/bin/bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 
read_os

JETPACK=/opt/cycle/jetpack/bin/jetpack

source $script_dir/../files/$os_release/rename_host.sh

function check_host_renaming() {
  delay=15
  n=1
  max_retry=3

  standalone_dns=$($JETPACK config cyclecloud.hosts.standalone_dns.enabled | tr '[:upper:]' '[:lower:]')
  if [[ $standalone_dns != "true" ]]; then
    # Get the target hostname
    target_hostname=$($JETPACK config cyclecloud.node.name | tr '[:upper:]' '[:lower:]')
    while true; do
      # Get current hostname
      current_hostname=$(hostname | tr '[:upper:]' '[:lower:]')
      # Get hostname associated with the IP address
      hostname_in_hosts=$(getent hosts $(ifconfig eth0 | grep "inet " | xargs) | xargs | cut -d ' ' -f2 | tr '[:upper:]' '[:lower:]' | cut -d'.' -f1)
      logger -s "Current hostname: $current_hostname"
      logger -s "Hostname returned by 'getent hosts': $hostname_in_hosts"
      logger -s "Target hostname: $target_hostname"
      if [[ "$current_hostname" != "$target_hostname" || "$target_hostname" != "$hostname_in_hosts" ]]; then
        logger -s "$target_hostname not fully renamed -  Attempt $n/$max_retry:"
        enforce_hostname $current_hostname $target_hostname
      else
        logger -s "hostname successfully renamed to $target_hostname"
        break
      fi
      if [[ $n -le $max_retry ]]; then
        sleep $delay
        ((n++))
      else
        logger -s "Failed to rename host $target_hostname after $max_retry attempts."
        exit 1
      fi
    done
    # Check if the new hostname is resolvable and loop until it is or max_retry is reached
    n=1
    max_retry=3
    while true; do
      logger -s "Checking if $target_hostname is resolvable"
      nslookup $target_hostname
      if [ $? -eq 0 ]; then
        break
      fi
      if [[ $n -le $max_retry ]]; then
        logger -s "$target_hostname not resolvable -  Attempt $n/$max_retry:"
        sleep $delay
        ((n++))
      else
        logger -s "Failed to resolved host $target_hostname after $max_retry attempts."
        exit 1
      fi
    done
  fi
}

if is_compute; then
  check_host_renaming
fi
