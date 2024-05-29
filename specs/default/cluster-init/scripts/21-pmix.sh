#!/bin/bash
set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 
read_os

PMIX_ROOT=/opt/pmix

# Configure PMIx if present in the image
# for these versions and above, PMIx is installed
#   - almalinux:almalinux-hpc:8_7-hpc-gen2:8.7.2024042601
#   - microsoft-dsvm:ubuntu-hpc:2004:20.04.2024043001
#   - microsoft-dsvm:ubuntu-hpc:2204:22.04.2024043001
#
function configure_pmix()
{
    # if the $PMIX_ROOT directory is not present, then exit on error as PMIx is required
    if [ ! -d $PMIX_ROOT ]; then
        logger -s "PMIx root directory $PMIX_ROOT not found"
        exit 0
    fi

    logger -s "Configuring PMIx for $os_release $os_version"

    case $os_release in
        almalinux)
            # Works out of the box
            ;;
        ubuntu)
            case $os_version in
                20.04 | 22.04)
                    PMIX_VERSION=4.2.9
                    PMIX_DIR=$PMIX_ROOT/$PMIX_VERSION
                    ln -s $PMIX_DIR/lib/libpmix.so /usr/lib/x86_64-linux-gnu/libpmix.so
                    # ln -s $PMIX_DIR/lib/libpmix.so /usr/lib/libpmix.so
                    ;;
                *)
                    logger -s "Untested OS $os_release $os_version"
                    exit 0
                    ;;
            esac
            ;;
        *)
            logger -s "Untested OS $os_release $os_version"
            exit 0
            ;;
    esac
}

if is_compute; then
    logger -s "Configuring PMIx"
    configure_pmix
    logger -s "PMIx configured successfully"
fi
