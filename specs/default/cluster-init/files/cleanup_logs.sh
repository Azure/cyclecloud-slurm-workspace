#!/bin/bash
cluster_name=$( jetpack config cyclecloud.cluster.name )
cleanup_logs_age=$( jetpack config cyclecloud.workspace.cleanup_logs_age )
set -e

if [ -z "$cluster_name" ]; then
  cluster_name="ccw"
fi

if [ -z "$cleanup_logs_age" ]; then
  cleanup_logs_age=7
fi

find "/shared/$cluster_name/node_logs/" -type f -mtime "+${cleanup_logs_age}" -exec rm -f {} \;
