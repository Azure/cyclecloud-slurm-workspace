#!/bin/bash
set -e

cluster_name=$(which scontrol > /dev/null && scontrol show config | grep -i "ClusterName" | sed 's/.*ClusterName *= *//')
find "/shared/$cluster_name/node_logs/" -type f -mtime +7 -exec rm -f {} \;
