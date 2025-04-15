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
    retry_command "yum update -y --exclude=cyclecloud*" 5 60
    retry_command "yum install -y jq"

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

# prod pid
# deployment_name='pid-d5d2708b-a4ef-42c0-a89b-b8bd6dd6d29b-partnercenter'
# dev pid
deployment_name='pid-b3313305-4e26-4c98-93c5-06d5412cb53d-partnercenter'
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
MANUAL=$(jq -r .manualInstall.value $ccw_root/ccwOutputs.json)

if [ "$MANUAL" == "true" ]; then
    echo "Manual install requested."
    if [ -z "$LOCAL_PACKAGE" ]; then
        echo "No local package path provided."
        echo "Copying install.sh to /opt/ccw and exiting."
        popd
        cp /var/lib/cloud/instance/user-data.txt $ccw_root/install.sh
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

FILES=$(jq -r .files.value ccwOutputs.json)
#get all the keys in FILES
keys=$(echo $FILES | jq -r 'keys[]')
for key in $keys; do
    # Split the string on '_'
    IFS='_' read -r -a split_key <<< "$key"
    # Take the last bit
    extension="${split_key[-1]}"
    filename="${key%_$extension}"
    filecontent=$(echo $FILES | jq -r .$key)
    # Print the file name
    echo "Processing $filename.$extension"
    # Create the file with the value decoded from base 64
    echo $filecontent | base64 --decode > "$filename.$extension"
done
while [ ! -f "$SECRETS_FILE_PATH" ]; do
    echo "Waiting for VM to create secrets file..."
    sleep 1
done
DATABASE_ADMIN_PASSWORD=$(jq -r .databaseAdminPassword $SECRETS_FILE_PATH)

CYCLECLOUD_USERNAME=$(jq -r .adminUsername.value ccwOutputs.json)
CYCLECLOUD_PASSWORD=$(jq -r .adminPassword "$SECRETS_FILE_PATH")
CYCLECLOUD_USER_PUBKEY=$(jq -r .publicKey.value ccwOutputs.json)
CYCLECLOUD_STORAGE="$(jq -r .storageAccountName.value ccwOutputs.json)"
SLURM_CLUSTER_NAME=$(jq -r .clusterName.value ccwOutputs.json)

# Copy the Slurm template and deployment outputs to the admin user's home directory
ADMIN_USER_HOME_DIR="/home/${CYCLECLOUD_USERNAME}"
SLURM_TEMPLATE_PATH=$(find /opt/cycle_server/system/work/.plugins_expanded/.expanded/cloud*/plugins/cloud/initial_data/templates/slurm/slurm_template_*.txt)
mkdir -p "${ADMIN_USER_HOME_DIR}/${SLURM_CLUSTER_NAME}"
cp "${SLURM_TEMPLATE_PATH}" "${ADMIN_USER_HOME_DIR}/${SLURM_CLUSTER_NAME}/slurm_template.txt"
cp ccwOutputs.json "${ADMIN_USER_HOME_DIR}/${SLURM_CLUSTER_NAME}/deployment.json"

if [[ "$MANUAL" == "true" ]]; then
    USE_INSIDERS_BUILD="false"
else
    USE_INSIDERS_BUILD=$(jq -r .insidersBuild.value ccwOutputs.json)
fi
MANAGED_IDENTITY_ID=$(jq -r .managedIdentityId.value ccwOutputs.json)

INCLUDE_OOD=true
if [ $(jq -r .ood.value.type ccwOutputs.json) == 'disabled'  ]; then
    INCLUDE_OOD=false
fi

INSIDERS_BUILD_ARG=
if [ "$USE_INSIDERS_BUILD" == "true" ] || [ "$MANUAL" == "true" ]; then
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
    if [ "$MANUAL" == "true" ]; then 
        echo "Now installing the cyclecloud8 build from local package."
        if command -v apt; then
            retry_command "apt install -y $LOCAL_PACKAGE"
        else
            retry_command "yum install -y $LOCAL_PACKAGE"
        fi
        echo "Successfully installed the cyclecloud8 build from local package."
    fi
fi

ACCEPT_MP_TERMS=$(jq -r .acceptMarketplaceTerms.value ccwOutputs.json)
MP_TERMS_ARG=
if [ "$ACCEPT_MP_TERMS" == "true" ]; then
    MP_TERMS_ARG="--acceptMarketplaceTerms"
fi

python3 /opt/ccw/cyclecloud_install.py --acceptTerms $MP_TERMS_ARG \
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

echo Waiting for records to be imported
timeout 360s bash -c 'until (! ls /opt/cycle_server/config/data/*.txt 2> /dev/null); do sleep 10; done'

echo Restarting cyclecloud so that new records take effect
cycle_server stop
cycle_server start --wait
# this will block until CC responds
curl -k https://localhost

cyclecloud initialize --batch --url=https://localhost --username=${CYCLECLOUD_USERNAME} --password=${CYCLECLOUD_PASSWORD} --verify-ssl=false --name=$SLURM_CLUSTER_NAME
echo "CC CLI initialize successful"

# Ensure CC properly initializes
lockerStatus=
while  [ -z "$lockerStatus" ]; do 
    for i in $(seq 1 24); do
        lockerStatus=$(/opt/cycle_server/./cycle_server execute 'select * from Cloud.Locker Where State=="Created" && Name=="azure-storage"')
        if [ -n "$lockerStatus" ]; then
            break
        fi
        sleep 5
    done
    # We strictly need to retry creating the locker record after waiting for two minutes, not after each successive check at the 5 second interval mark
    # Resetting too frequently will cause the locker record to never be created as needed
    if [ -z "$lockerStatus" ]; then
        /opt/cycle_server/./cycle_server run_action Retry:Cloud.Locker -f 'Name=="azure-storage"'
    fi
done

# needs to be done after initialization, as we now call fetch/upload
(python3 create_cc_param.py slurm --dbPassword="${DATABASE_ADMIN_PASSWORD}") > slurm_params.json 

# copying template parameters file to admin user's home directory
cp slurm_params.json "${ADMIN_USER_HOME_DIR}/${SLURM_CLUSTER_NAME}/slurm_params.json"

SLURM_PROJ_VERSION=$(cycle_server execute --format json 'SELECT Version FROM Cloud.Project WHERE Name=="Slurm"' | jq -r '.[0].Version')

cyclecloud create_cluster slurm_template_${SLURM_PROJ_VERSION} $SLURM_CLUSTER_NAME -p slurm_params.json
echo "CC create_cluster successful"

## BEGIN temporary login node max count patch
# TODO After azslurm 3.0.12 is released we should have a proper parameter for maxcount for login nodes
LOGIN_NODES_MAX_COUNT=$(jq -r '.loginNodes.value.maxNodes' ccwOutputs.json)
# ensure the value is actually an integer
python3 -c "import sys; int(sys.argv[1])" $LOGIN_NODES_MAX_COUNT
/opt/cycle_server/./cycle_server execute "UPDATE Cloud.Node \
                                          SET MaxCount=${LOGIN_NODES_MAX_COUNT} \
                                          WHERE ClusterName==\"$SLURM_CLUSTER_NAME\" && Name==\"login\""
## END temporary login node max count patch

if [ $INCLUDE_OOD == true ]; then
    # When we add OOD as an icon to CycleCloud, only parameter creation and create_cluster calls should
    # remain. The fetch / upload / import_template calls should be removed.
    (python3 create_cc_param.py ood) > ood_params.json 

    OOD_PROJECT_VERSION=$(jq -r .ood.value.version ccwOutputs.json)
    ood_url="https://github.com/Azure/cyclecloud-open-ondemand/releases/${OOD_PROJECT_VERSION}"
    echo fetching OOD project from $ood_url
    cyclecloud project fetch $ood_url ood
    cd ood
    cyclecloud project upload azure-storage
    ood_template_name=OpenOnDemand_${OOD_PROJECT_VERSION}
    cyclecloud import_template -c OpenOnDemand -f templates/OpenOnDemand.txt $ood_template_name --force
    cd ..
    cyclecloud create_cluster $ood_template_name OpenOnDemand -p ood_params.json
fi
# ensure machine types are loaded ASAP
cycle_server run_action 'Run:Application.Timer' -eq 'Name' 'plugin.azure.monitor_reference'

# Wait for Azure.MachineType to be populated
while [ $(/opt/cycle_server/./cycle_server execute --format json "
                        SELECT Name, M.Name as MachineType FROM Cloud.Node
                        OUTER JOIN Azure.MachineType M
                        ON  MachineType === M.Name &&
                            Region === M.Location
                        WHERE (ClusterName == "OpenOnDemand" || ClusterName == \"$SLURM_CLUSTER_NAME\")" | jq -r ".[] | select(.MachineType == null).Name" | wc -l) != 0 ]; do
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

START_SLURM_CLUSTER=$(jq -r .slurmSettings.value.startCluster ccwOutputs.json)
if [ "$START_SLURM_CLUSTER" == "true" ]; then
    cyclecloud start_cluster "$SLURM_CLUSTER_NAME"
    echo "CC start_cluster for $SLURM_CLUSTER_NAME successful"
fi
rm -f slurm_params.json
echo "Deleted Slurm input parameters file" 

if [ $INCLUDE_OOD == true ]; then
    START_OOD_CLUSTER=$(jq -r .ood.value.startCluster ccwOutputs.json)
    if [ "$START_OOD_CLUSTER" == "true" ]; then
        cyclecloud start_cluster OpenOnDemand
        echo "CC start_cluster for OpenOnDemand successful"
    fi
    rm -f ood_params.json
    echo "Deleted OOD input parameters file" 
fi

#TODO next step: wait for scheduler node to be running, get IP address of scheduler + login nodes (if enabled)
popd

rm -f "$SECRETS_FILE_PATH"
echo "Deleting secrets file"
echo "exiting after install"
exit 0