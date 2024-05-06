#!/bin/bash
set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 
read_os

ENROOT_VERSION=3.4.1

function install_enroot() {
    # Install or update enroot if necessary
    if [ "$(enroot version)" != "$ENROOT_VERSION" ] ; then
        logger -s  Updating enroot to $ENROOT_VERSION
        case $os_release in
            almalinux)
                yum remove -y enroot enroot+caps
                arch=$(uname -m)
                yum install -y https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot-${ENROOT_VERSION}-1.el8.${arch}.rpm
                yum install -y https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot+caps-${ENROOT_VERSION}-1.el8.${arch}.rpm
                ;;
            ubuntu)
                arch=$(dpkg --print-architecture)
                curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot_${ENROOT_VERSION}-1_${arch}.deb
                curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v${ENROOT_VERSION}/enroot+caps_${ENROOT_VERSION}-1_${arch}.deb
                apt install -y ./*.deb
                ;;
            *)
                logger -s "OS $os_release not tested"
                exit 0
            ;;
        esac
    else
        logger -s  Enroot is already at version $ENROOT_VERSION
    fi
}

function configure_enroot() 
{
    # enroot default scratch dir to /mnt/enrot
    # If NVMe disks exists link /mnt/enroot to /mnt/nvme/enroot
    ENROOT_SCRATCH_DIR=/mnt/enroot
    if [ -d /mnt/nvme ]; then
        # If /mnt/nvme exists, use it as the default scratch dir
        mkdir -pv /mnt/nvme/enroot
        ln -s /mnt/nvme/enroot /mnt/enroot
    else
        mkdir -pv /mnt/scratch/enroot
        ln -s /mnt/nvme/enroot /mnt/enroot
    fi

    logger -s "Creating enroot scratch directories in $ENROOT_SCRATCH_DIR"
    mkdir -pv /run/enroot $ENROOT_SCRATCH_DIR/{enroot-cache,enroot-data,enroot-temp,enroot-runtime}
    chmod -v 777 /run/enroot $ENROOT_SCRATCH_DIR/{enroot-cache,enroot-data,enroot-temp,enroot-runtime}

    # Configure enroot
    # https://github.com/NVIDIA/pyxis/wiki/Setup
    logger -s "Configure /etc/enroot/enroot.conf"
    cat <<EOF > /etc/enroot/enroot.conf
ENROOT_RUNTIME_PATH /run/enroot/user-\$(id -u)
ENROOT_CACHE_PATH $ENROOT_SCRATCH_DIR/enroot-cache/group-\$(id -g)
ENROOT_DATA_PATH $ENROOT_SCRATCH_DIR/enroot-data/user-\$(id -u)
ENROOT_TEMP_PATH $ENROOT_SCRATCH_DIR/enroot-temp
ENROOT_SQUASH_OPTIONS -noI -noD -noF -noX -no-duplicates
ENROOT_MOUNT_HOME y
ENROOT_RESTRICT_DEV y
ENROOT_ROOTFS_WRITABLE y
MELLANOX_VISIBLE_DEVICES all
EOF

    logger -s "Install extra hooks for PMIx on compute nodes"
    cp -fv /usr/share/enroot/hooks.d/50-slurm-pmi.sh /usr/share/enroot/hooks.d/50-slurm-pytorch.sh /etc/enroot/hooks.d
}

if is_compute ; then
    install_enroot
    configure_enroot
fi
