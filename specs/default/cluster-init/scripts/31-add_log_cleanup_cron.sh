#!/bin/bash
set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

if [ ! is_scheduler ]; then 
    exit 0
fi

cat << EOF > /etc/cron.daily/node_log_cleanup
#!/bin/bash
set -e

cluster_name=$(which scontrol > /dev/null && scontrol show config | grep -i "ClusterName" | sed 's/.*ClusterName *= *//')
find "/shared/$cluster_name/node_logs/" -type f -mtime +7 -exec rm -f {} \;
EOF