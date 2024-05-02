#!/bin/bash
set -e
PMIX_VERSION=4.2.9
PMIX_ROOT=/opt/pmix
PMIX_DIR=$PMIX_ROOT/$PMIX_VERSION

logger -s "Configuring PMIx"

function build_pmix()
{
    # Build PMIx
    logger -s "Build PMIx"
    cd /mnt/scratch
	rm -rf pmix-${PMIX_VERSION}
    wget -q https://github.com/openpmix/openpmix/releases/download/v$PMIX_VERSION/pmix-$PMIX_VERSION.tar.gz
    tar -xzf pmix-$PMIX_VERSION.tar.gz
    cd pmix-$PMIX_VERSION

    ./autogen.pl
    ./configure --prefix=$PMIX_DIR
    make -j install
	cd ..
	rm -rf pmix-${PMIX_VERSION}
    rm pmix-$PMIX_VERSION.tar.gz
    logger -s "PMIx Sucessfully Installed"
}

function configure_slurmd()
{
    logger -s "Configure PMIx in Slurm service"
    [ -d /etc/sysconfig ] || mkdir -pv /etc/sysconfig
    # while [ ! -f /etc/sysconfig/slurmd ]
    # do
    #     sleep 2
    # done
    set +e
    grep -q PMIX_MCA /etc/sysconfig/slurmd
    pmix_is_not_set=$?
    set -e
    if [ $pmix_is_not_set ]; then
        # slurmd environment variables for PMIx
        logger -s "Set PMIx environment variables in slurmd"
cat <<EOF >> /etc/sysconfig/slurmd

PMIX_MCA_ptl=^usock
PMIX_MCA_psec=none
PMIX_SYSTEM_TMPDIR=/var/empty
PMIX_MCA_gds=hash
HWLOC_COMPONENTS=-opencl
EOF
    logger -s "Restart slurmd service to apply PMIx configuration"
    systemctl restart slurmd
    fi
}

# Install PMIx if not present in the image
# for almalinux:almalinux-hpc:8_7-hpc-gen2:8.7.2024042601 and above PMIx is already installed
# if the $PMIX_ROOT directory is not present, then install PMIx
if [ ! -d $PMIX_ROOT ]; then
    os_release=$(cat /etc/os-release | grep "^ID\=" | cut -d'=' -f 2 | xargs)
    case $os_release in
        rhel|almalinux)
            logger -s "Installing PMIx $PMIX_VERSION for $os_release"
            yum -y install pmix-$PMIX_VERSION-1.el8
            ;;
        ubuntu|debian)
            logger -s "Installing PMIx dependencies for $os_release"
            apt-get update
            #apt-get install -y git libevent-dev libhwloc-dev autoconf flex make gcc libxml2
            apt-get install -y libevent-dev libhwloc-dev
            build_pmix
            ln -s $PMIX_DIR/lib/libpmix.so /usr/lib/libpmix.so
            ;;
    esac
fi

configure_slurmd
logger -s "PMIx configured successfully"
