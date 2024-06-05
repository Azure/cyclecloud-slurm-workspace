#!/bin/bash
set -eo pipefail
# this is not set if you run this manually
export PATH=$PATH:/usr/local/bin
ccsw_root="/opt/ccsw"
mkdir -p -m 777 $ccsw_root

read_os()
{
    os_release=$(cat /etc/os-release | grep "^ID\=" | cut -d'=' -f 2 | xargs)
    os_maj_ver=$(cat /etc/os-release | grep "^VERSION_ID\=" | cut -d'=' -f 2 | xargs)
    full_version=$(cat /etc/os-release | grep "^VERSION\=" | cut -d'=' -f 2 | xargs)
}

retry_command() {
    local cmd=$1
    local retries=${2:-5}
    local delay=${3:-10}

    set +eo pipefail

    for ((i=0; i<retries; i++)); do
        echo "Running command: $cmd"
        $cmd

        if [ $? -eq 0 ]; then
            echo "Command succeeded!"
            set -eo pipefail
            return 0
        else
            echo "Command failed. Retrying in ${delay}s..."
            sleep $delay
        fi
    done

    echo "Command failed after $retries retries."
    set -eo pipefail
    return 1
}
read_os

# echo "* apt updating"
# retry_command "apt update"

# replaces retry_command "./toolset/scripts/install.sh"
curl -L -o /tmp/azcopy_linux.tar.gz 'https://aka.ms/downloadazcopy-v10-linux'
tar xzf /tmp/azcopy_linux.tar.gz -C /tmp/ 
mv /tmp/azcopy_linux*/azcopy /usr/local/bin/azcopy 
rm -rf /tmp/azcopy_linux*
# curl -L -o /usr/local/bin/yq 'https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64'
# chmod a+x /usr/local/bin/yq
if command -v apt; then
    retry_command "apt update -y"
    #apt install -y 
else
    retry_command "yum update -y"
    retry_command "yum install -y wget jq"
    #yum install -y 
fi
printf "\n\n"
printf "Applications installed\n"
printf "===============================================================================\n"
columns="%-16s| %.10s\n"
printf "$columns" Application Version
printf -- "-------------------------------------------------------------------------------\n"
printf "$columns" Python `python3 --version | awk '{ print $2 }'`
printf "$columns" az-cli `az --version 2> /dev/null | head -n 1 | awk '{ print $2 }'`
printf "$columns" azcopy `azcopy --version | awk '{ print $3 }'`
# printf "$columns" yq `yq --version | awk '{ print $4 }'`
printf "===============================================================================\n"

echo "* Logging in to Azure"
mds=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2018-10-01")
cloudenv=$(echo $mds | jq -r '.compute.azEnvironment' | tr '[:upper:]' '[:lower:]')
if [ "$cloudenv" == "azureusgovernmentcloud" ]; then
    echo "Running in Azure US Government Cloud"
    az cloud set --name AzureUSGovernment
fi
#FIX REMOVE SLEEP
sleep 60
# Add retry logic as it could take some delay to apply the Managed Identity
timeout 360s bash -c 'until az login -i; do sleep 10; done'

deployment_name='pid-8d5b25bd-0ba7-49b9-90b3-3472bc08443e-partnercenter'
resource_group=$(echo $mds | jq -r '.compute.resourceGroupName')
vm_id=$(echo $mds | jq -r '.compute.vmId')

echo "* Waiting for deployment to complete"
while deployment_state=$(az deployment group show -g $resource_group -n $deployment_name --query properties.provisioningState -o tsv); [ "$deployment_state" != "Succeeded" ]; do
    echo "Deployment is not yet complete (currently $deployment_state). Waiting..."
    sleep 10
done

mkdir -p $ccsw_root/bin

# FOR TESTING PURPOSES
pushd $ccsw_root
az deployment group show -g $resource_group -n $deployment_name --query properties.outputs > ccswOutputs.json

BRANCH=$(jq -r .branch.value ccswOutputs.json)
URI="https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/$BRANCH/bicep/files-to-load"

# we don't want slurm-workspace.txt.1 etc if someone reruns this script, so use -O to overwrite existing files
wget -O slurm-workspace.txt $URI/slurm-workspace.txt
wget -O create_cc_param.py $URI/create_cc_param.py
wget -O initial_params.json $URI/initial_params.json
wget -O cyclecloud_install.py $URI/cyclecloud_install.py
(python3 create_cc_param.py) > slurm_params.json
echo "Filework successful" 

CYCLECLOUD_USERNAME=$(jq -r .ccswGlobalConfig.value.adminUsername ccswOutputs.json)
CYCLECLOUD_PASSWORD=$(jq -r .ccswGlobalConfig.value.adminPassword ccswOutputs.json)
CYCLECLOUD_USER_PUBKEY=$(jq -r .ccswGlobalConfig.value.publicKey ccswOutputs.json)
CYCLECLOUD_STORAGE="$(jq -r .ccswGlobalConfig.value.global_cc_storage ccswOutputs.json)"
python3 /opt/ccsw/cyclecloud_install.py --acceptTerms \
    --useManagedIdentity --username=${CYCLECLOUD_USERNAME} --password="${CYCLECLOUD_PASSWORD}" \
    --publickey="${CYCLECLOUD_USER_PUBKEY}" \
    --storageAccount=${CYCLECLOUD_STORAGE} \
    --webServerPort=80 --webServerSslPort=443
sleep 30
echo "CC install script successful"
# Configuring distribution_method
cat > /tmp/ccsw_site_id.txt <<EOF
AdType = "Application.Setting"
Name = "site_id"
Value = "${vm_id}"

AdType = "Application.Setting"
Name = "distribution_method"
Value = "ccsw"
EOF
chown cycle_server:cycle_server /tmp/ccsw_site_id.txt
chmod 664 /tmp/ccsw_site_id.txt
mv /tmp/ccsw_site_id.txt /opt/cycle_server/config/data/ccsw_site_id.txt

# Create the project file
# TODO: Add the version number in the Url
cat > /opt/cycle_server/config/data/ccsw_project.txt <<EOF
AdType = "Cloud.Project"
Version = "1.0.0"
ProjectType = "scheduler"
Url = "https://github.com/Azure/cyclecloud-slurm-workspace"
AutoUpgrade = false
Name = "ccsw"
EOF

#sudo -i -u $CYCLECLOUD_USERNAME #TODO test this with CC initialize  
cyclecloud initialize --batch --url=https://localhost --username=${CYCLECLOUD_USERNAME} --password=${CYCLECLOUD_PASSWORD} --verify-ssl=false --name=ccsw
echo "CC initialize successful"
sleep 5
cyclecloud import_template Slurm-Workspace -f slurm-workspace.txt
echo "CC import template successful"
cyclecloud create_cluster Slurm-Workspace ccsw -p slurm_params.json
echo "CC create_cluster successful"

# Wait for Azure.MachineType to be populated
while ! (cycle_server execute 'select * from Azure.MachineType' | grep -q Standard); do
    echo "Waiting for Azure.MachineType to be populated..."
    sleep 10
done

cyclecloud start_cluster ccsw
echo "CC start_cluster successful"
#TODO next step: wait for scheduler node to be running, get IP address of scheduler + login nodes (if enabled)
popd
echo "exiting after install"
exit 0