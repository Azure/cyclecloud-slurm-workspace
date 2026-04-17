#!/bin/bash
# Install ARM TTK in order to validate ARM templates
set -e
GIT_ROOT=$(git rev-parse --show-toplevel)

# from https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.4
###################################
# Prerequisites

# Update the list of packages
sudo apt-get update

# Install pre-requisite packages.
sudo apt-get install -y wget unzip

# TODO : Check if powershell is already installed before doing the following steps
if ! dpkg -l powershell ; then
    # Download the PowerShell package file
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.4.2/powershell_7.4.2-1.deb_amd64.deb

    ###################################
    # Install the PowerShell package
    sudo dpkg -i powershell_7.4.2-1.deb_amd64.deb

    # Resolve missing dependencies and finish the install (if necessary)
    sudo apt-get install -f

    # Delete the downloaded package file
    rm powershell_7.4.2-1.deb_amd64.deb
fi

# if arm-ttk is already installed, skip this step
if [ -d "$GIT_ROOT/arm-ttk" ]; then
    echo "arm-ttk is already installed"
    exit 0
fi

LATEST_VERSION=$(curl -s https://api.github.com/repos/Azure/arm-ttk/releases/latest | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
wget "https://github.com/Azure/arm-ttk/releases/download/${LATEST_VERSION}/arm-ttk.zip"
unzip -u arm-ttk.zip -d $GIT_ROOT
rm arm-ttk.zip
chmod +x $GIT_ROOT/arm-ttk/arm-ttk/Test-AzTemplate.sh

