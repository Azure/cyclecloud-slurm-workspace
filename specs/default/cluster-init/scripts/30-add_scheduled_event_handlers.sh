#!/bin/bash
set -ex
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

collect_logs_script="$script_dir/../files/collect_logs.sh" 
chmod 770 ${collect_logs_script}

mkdir -p /opt/cycle/jetpack/scripts

cat << EOF > /opt/cycle/jetpack/scripts/onTerminate.sh
bash -c ${collect_logs_script}

EOF
chmod 770 /opt/cycle/jetpack/scripts/onTerminate.sh
