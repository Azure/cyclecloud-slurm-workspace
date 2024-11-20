#!/bin/bash
set -ex
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

if is_scheduler; then 
    exit 0
fi

logger -s "Adding termination event handler to collect logs at /opt/cycle/jetpack/scripts/onTerminate.sh"

collect_logs_script="$script_dir/../files/collect_logs.sh" 
chmod 770 "${collect_logs_script}"

mkdir -p /opt/cycle/jetpack/scripts

cat << EOF > /opt/cycle/jetpack/scripts/onTerminate.sh
#!/bin/bash
set -e
bash "${collect_logs_script}"

EOF
chmod 770 /opt/cycle/jetpack/scripts/onTerminate.sh
