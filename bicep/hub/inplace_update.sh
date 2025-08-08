#!/bin/bash
set -e
cd "$(dirname "$0")"

# Identify cyclecloud8 build version
INITIAL_CC_BUILD_VERSION=$(cat /opt/cycle_server/system/version)

# Update cyclecloud yum repo to insiders-fast 
sed -i 's|^\(baseurl=.*\)/cyclecloud$|\1/cyclecloud-insiders-fast|' /etc/yum.repos.d/cyclecloud.repo

# Clean and rebuild yum cache
yum clean all
yum makecache

# Update cyclecloud8 to latest version
yum -y update cyclecloud8

# Check if the update was successful
UPDATED_CC_BUILD_VERSION=$(cat /opt/cycle_server/system/version)
if [ "$UPDATED_CC_BUILD_VERSION" != "$INITIAL_CC_BUILD_VERSION" ]; then
    echo "CycleCloud updated successfully from version $INITIAL_CC_BUILD_VERSION to $UPDATED_CC_BUILD_VERSION."
else
    echo "CycleCloud update failed or no new version available."
    exit 1
fi

# Update cyclecloud-monitoring project to latest release 
/usr/local/bin/cyclecloud project fetch https://github.com/Azure/cyclecloud-monitoring/releases/1.0.2 /tmp/cyclecloud-monitoring
pushd /tmp/cyclecloud-monitoring
/usr/local/bin/cyclecloud project upload azure-storage
popd
rm -rf /tmp/cyclecloud-monitoring

# Insert CC-Slurm 4.0.0 project record
cat >/opt/cycle_server/config/data/slurm400.txt<<EOF

AdType = "Cloud.Project"
Version = "4.0.0"
ProjectType = "scheduler"
Url = "https://github.com/Azure/cyclecloud-slurm/releases/4.0.0"
AutoUpgrade = false
Name = "slurm"

EOF

# Confirm insertion of Slurm 4.0.0 project record
echo "Inserting Slurm 4.0.0 project record..."
sleep 10
if [ $(/opt/cycle_server/./cycle_server execute --format json "SELECT Version FROM Cloud.Project WHERE ProjectType == \"scheduler\" &&  Name == \"Slurm\"" | jq '[.[] | .Version]' | grep 4.0.0 | wc -l) != 0 ]; then
    echo "Slurm 4.0.0 project record inserted successfully."
else
    echo "Failed to insert Slurm 4.0.0 project record."
    exit 1
fi

echo "In-place update completed successfully."