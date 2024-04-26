#!/bin/bash

function enforce_hostname() {
  local system_hostname=$1
  local target_hostname=$2

  logger -s "Ensure that the correct hostname has been set and update if necessary"
  if [ "$system_hostname" != "$target_hostname" ]; then
    logger -s "Warning: incorrect hostname ($system_hostname), it should be $target_hostname, updating"
    hostname $target_hostname
  fi
  logger -s "Check in /etc/hosts"
  hostname_in_hosts=$(getent hosts $(ifconfig eth0 | grep "inet " | xargs) | xargs | cut -d ' ' -f2 | tr '[:upper:]' '[:lower:]')
  if [ "$hostname_in_hosts" != "$target_hostname" ]; then
    logger -s "Warning: incorrect hostname ($hostname_in_hosts) in /etc/hosts, updating"
    sed -i "s/$hostname_in_hosts/$target_hostname/ig" /etc/hosts
  fi
  logger -s "Check in /etc/hostname"
  etc_hostname=$(</etc/hostname)
  if [ "$etc_hostname" != "$target_hostname" ]; then
    logger -s "Warning: incorrect /etc/hostname ($etc_hostname), it should be $target_hostname, updating"
    echo $target_hostname > /etc/hostname
  fi

  if ! systemctl restart systemd-networkd; then
    logger -s "failed to restart systemd-networkd"
  fi
}