#!/bin/bash
cluster_name=$( jetpack config cyclecloud.cluster.name )
set -e

if [ -z "$cluster_name" ]; then
  cluster_name="ccw"
fi

find "/shared/$cluster_name/node_logs/" -type f -mtime +7 -exec rm -f {} \;
