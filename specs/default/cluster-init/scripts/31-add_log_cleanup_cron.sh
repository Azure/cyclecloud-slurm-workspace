#!/bin/bash
set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

if [ ! is_scheduler ]; then 
    exit 0
fi

cleanup_logs_script="$script_dir/../files/cleanup_logs.sh" 
chmod 770 "${cleanup_logs_script}"

cat << EOF > /etc/cron.daily/node_log_cleanup
#!/bin/bash
set -e
bash "${cleanup_logs_script}"

EOF