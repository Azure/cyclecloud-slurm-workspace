#!/bin/bash

set -eo pipefail
# this is not set if you run this manually
export PATH=$PATH:/usr/local/bin
ccw_root="/opt/ccw"
mkdir -p -m 777 $ccw_root

# DEV USER: Set this to the path of your build
LOCAL_PACKAGE=""

while (( "$#" )); do
        case $1 in
                --local-package) 
                    if [ -z "$2" ]; then
                        echo "--local-package requires a non-empty argument." >&2
                        exit 1
                    fi
                    LOCAL_PACKAGE="$2"
                    shift
                    ;;
                *) 
                    echo "Unknown parameter passed: $1"
                    exit 1
                    ;;
        esac
        shift
done


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

# Install azcopy prior to manual deployment cutoff so the dev user has the option to copy their build
echo "* Installing azcopy"
curl -L -o /tmp/azcopy_linux.tar.gz 'https://aka.ms/downloadazcopy-v10-linux'
tar xzf /tmp/azcopy_linux.tar.gz -C /tmp/ 
mv /tmp/azcopy_linux*/azcopy /usr/local/bin/azcopy 
rm -rf /tmp/azcopy_linux*

echo "* Updating the system"
if command -v apt; then
    apt-mark hold cyclecloud8
    apt-mark hold jetpack8
    retry_command "apt update -y"
    #apt install -y 
else
    retry_command "yum update -y --exclude=cyclecloud*"
    retry_command "yum install -y wget jq"

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
    env="usgov" # ="china" for CN, "germany" for DE
else
    echo "Running in Azure Public Cloud"
    az cloud set --name AzureCloud
    env="public"
fi
# Add retry logic as it could take some delay to apply the Managed Identity
timeout 360s bash -c 'until az login -i; do sleep 10; done'

deployment_name='pid-d5d2708b-a4ef-42c0-a89b-b8bd6dd6d29b-partnercenter'
resource_group=$(echo $mds | jq -r '.compute.resourceGroupName')
vm_id=$(echo $mds | jq -r '.compute.vmId')

echo "* Waiting for deployment to complete"
while deployment_state=$(az deployment group show -g $resource_group -n $deployment_name --query properties.provisioningState -o tsv); [ "$deployment_state" != "Succeeded" ]; do
    echo "Deployment is not yet complete (currently $deployment_state). Waiting..."
    sleep 10
done

pushd $ccw_root
echo "* Extracting deployment output"
az deployment group show -g $resource_group -n $deployment_name --query properties.outputs > ccwOutputs.json
BRANCH=$(jq -r .branch.value $ccw_root/ccwOutputs.json)
URI="https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/$BRANCH/bicep"
MANUAL=$(jq -r .manualInstall.value $ccw_root/ccwOutputs.json)

if [ "$MANUAL" == "true" ]; then
    echo "Manual install requested."
    if [ -z "$LOCAL_PACKAGE" ]; then
        echo "No local package path provided."
        echo "Copying install.sh to /opt/ccw and exiting."
        wget -O install.sh $URI/install.sh
        popd
        exit 0
    else 
        echo "Local package path provided."
        if [[ ! -f "$LOCAL_PACKAGE" ]]; then
            echo "No file found at $LOCAL_PACKAGE. Exiting."
            popd 
            exit 0
        else 
            echo "File found at $LOCAL_PACKAGE. Continuing."
        fi
    fi
fi

mkdir -p $ccw_root/bin

PROJECT_VERSION=$(jq -r .projectVersion.value ccwOutputs.json)
SECRETS_FILE_PATH="/root/ccw.secrets.json"

# we don't want slurm-workspace.txt.1 etc if someone reruns this script, so use -O to overwrite existing files
wget -O slurm-workspace.txt $URI/files-to-load/slurm-workspace.txt
wget -O create_cc_param.py $URI/files-to-load/create_cc_param.py
wget -O initial_params.json $URI/files-to-load/initial_params.json
wget -O cyclecloud_install.py $URI/files-to-load/cyclecloud_install.py
while [ ! -f "$SECRETS_FILE_PATH" ]; do
    echo "Waiting for VM to create secrets file..."
    sleep 1
done
DATABASE_ADMIN_PASSWORD=$(jq -r .databaseAdminPassword $SECRETS_FILE_PATH)
(python3 create_cc_param.py --dbPassword="${DATABASE_ADMIN_PASSWORD}") > slurm_params.json
echo "Filework successful" 

CYCLECLOUD_USERNAME=$(jq -r .adminUsername.value ccwOutputs.json)
CYCLECLOUD_PASSWORD=$(jq -r .adminPassword "$SECRETS_FILE_PATH")
CYCLECLOUD_USER_PUBKEY=$(jq -r .publicKey.value ccwOutputs.json)
CYCLECLOUD_STORAGE="$(jq -r .storageAccountName.value ccwOutputs.json)"
SLURM_CLUSTER_NAME=$(jq -r .clusterName.value ccwOutputs.json)
if [[ "$MANUAL" == "true" ]]; then
    USE_INSIDERS_BUILD="false"
else
    USE_INSIDERS_BUILD=$(jq -r .insidersBuild.value ccwOutputs.json)
fi
MANAGED_IDENTITY_ID=$(jq -r .managedIdentityId.value ccwOutputs.json)
INSIDERS_BUILD_ARG=
if [ "$USE_INSIDERS_BUILD" == "true" ] || [ -e $LOCAL_PACKAGE ]; then
    if [ "$USE_INSIDERS_BUILD" == "true" ]; then 
        echo -n "Using insiders build"
        INSIDERS_BUILD_ARG="--insidersBuild"
    else 
        echo -n "Using local package build"
    fi
    echo " - we first need to uninstall cyclecloud8 and remove all files."
    if command -v apt; then
        apt remove -y cyclecloud8
    else
        yum remove -y cyclecloud8
    fi
    rm -rf /opt/cycle_server/*
    echo "cyclecloud8 is uninstalled and all files are removed under /opt/cycle_server."
    if [ -e $LOCAL_PACKAGE ]; then 
        echo "Now installing the cyclecloud8 build from local package."
        if command -v apt; then
            retry_command "apt install -y $LOCAL_PACKAGE"
        else
            retry_command "yum install -y $LOCAL_PACKAGE"
        fi
        echo "Successfully installed the cyclecloud8 build from local package."
    fi
fi

python3 /opt/ccw/cyclecloud_install.py --acceptTerms \
    --useManagedIdentity --username=${CYCLECLOUD_USERNAME} --password="${CYCLECLOUD_PASSWORD}" \
    --publickey="${CYCLECLOUD_USER_PUBKEY}" \
    --storageAccount=${CYCLECLOUD_STORAGE} \
    --azureSovereignCloud="${env}" \
    --webServerPort=80 --webServerSslPort=443 $INSIDERS_BUILD_ARG --storageManagedIdentity="${MANAGED_IDENTITY_ID}"

echo "CC install script successful"
# Configuring distribution_method
cat > /tmp/ccw_site_id.txt <<EOF
AdType = "Application.Setting"
Name = "site_id"
Value = "${vm_id}"

AdType = "Application.Setting"
Name = "distribution_method"
Value = "ccw-$PROJECT_VERSION"
EOF
chown cycle_server:cycle_server /tmp/ccw_site_id.txt
chmod 664 /tmp/ccw_site_id.txt
mv /tmp/ccw_site_id.txt /opt/cycle_server/config/data/ccw_site_id.txt

# Create the project file
cat > /opt/cycle_server/config/data/ccw_project.txt <<EOF
AdType = "Cloud.Project"
Version = "$PROJECT_VERSION"
ProjectType = "scheduler"
Url = "https://github.com/Azure/cyclecloud-slurm-workspace/releases/$PROJECT_VERSION"
AutoUpgrade = false
Name = "ccw"
EOF

echo Waiting for records to be imported
timeout 360s bash -c 'until (! ls /opt/cycle_server/config/data/*.txt); do sleep 10; done'

echo Restarting cyclecloud so that new records take effect
cycle_server stop
cycle_server start --wait
# this will block until CC responds
curl -k https://localhost

cyclecloud initialize --batch --url=https://localhost --username=${CYCLECLOUD_USERNAME} --password=${CYCLECLOUD_PASSWORD} --verify-ssl=false --name=$SLURM_CLUSTER_NAME
echo "CC initialize successful"
sleep 5
cyclecloud import_template Slurm-Workspace -f slurm-workspace.txt
echo "CC import template successful"
cyclecloud create_cluster Slurm-Workspace $SLURM_CLUSTER_NAME -p slurm_params.json
echo "CC create_cluster successful"

# ensure machine types are loaded ASAP
cycle_server run_action 'Run:Application.Timer' -eq 'Name' 'plugin.azure.monitor_reference'

# Wait for Azure.MachineType to be populated
while [ $(/opt/cycle_server/./cycle_server execute --format json "
                        SELECT Name, M.Name as MachineType FROM Cloud.Node
                        OUTER JOIN Azure.MachineType M
                        ON  MachineType === M.Name &&
                            Region === M.Location
                        WHERE clustername==\"$SLURM_CLUSTER_NAME\"" | jq -r ".[] | select(.MachineType == null).Name" | wc -l) != 0 ]; do
    echo "Waiting for Azure.MachineType to be populated..."
    sleep 10
done
echo All Azure.MachineType records are loaded.

# Enable accel networking on any nodearray that has a VM Size that supports it.
/opt/cycle_server/./cycle_server execute \
"SELECT AdType, ClusterName, Name, M.AcceleratedNetworkingEnabled AS EnableAcceleratedNetworking
 FROM Cloud.Node
 INNER JOIN Azure.MachineType M 
 ON M.Name===MachineType && M.Location===Region
 WHERE ClusterName==\"$SLURM_CLUSTER_NAME\"" > /tmp/accel_network.txt
 mv /tmp/accel_network.txt /opt/cycle_server/config/data

# it usually takes less than 2 seconds, so before starting the longer timeouts, optimistically sleep.
sleep 2
echo Waiting for accelerated network records to be imported
timeout 360s bash -c 'until (! ls /opt/cycle_server/config/data/*.txt); do sleep 10; done'

cyclecloud start_cluster "$SLURM_CLUSTER_NAME"
echo "CC start_cluster successful"
# rm -f slurm_params.json
echo "Deleted input parameters file" 
#TODO next step: wait for scheduler node to be running, get IP address of scheduler + login nodes (if enabled)
popd
# rm -f "$SECRETS_FILE_PATH"
echo "Deleting secrets file"
echo "exiting after install"
exit 0