#!/bin/bash
set -e
PYXIS_VERSION=0.19.0
SHARED_DIR=/sched/pyxis

function link_plugstack() {
   [ ! -e /etc/slurm/plugstack.conf ] && ln -s /sched/plugstack.conf /etc/slurm/plugstack.conf
   [ ! -e /etc/slurm/plugstack.conf.d ] && ln -s /sched/plugstack.conf.d /etc/slurm/plugstack.conf.d
}

function install_plugstack() {
   mkdir -p /sched/plugstack.conf.d
   echo 'include /sched/plugstack.conf.d/*' > /sched/plugstack.conf
   chown -R slurm:slurm /sched/plugstack.conf
   echo 'required /usr/lib64/slurm/spank_pyxis.so runtime_path=/mnt/scratch/enroot-runtime' > /sched/plugstack.conf.d/pyxis.conf
   chown slurm:slurm /sched/plugstack.conf.d/pyxis.conf
   link_plugstack
}

# download source code in /mnt/scratch
logger -s "Downloading Pyxis source code $PYXIS_VERSION"

cd /tmp
wget -q https://github.com/NVIDIA/pyxis/archive/refs/tags/v$PYXIS_VERSION.tar.gz
tar -xzf v$PYXIS_VERSION.tar.gz
cd pyxis-$PYXIS_VERSION
logger -s "Building Pyxis"
make

# Copy pyxis library to cluster shared directory
logger -s "Copying Pyxis library to $SHARED_DIR"
mkdir -p ${SHARED_DIR}
cp -fv spank_pyxis.so ${SHARED_DIR}
chmod +x ${SHARED_DIR}/spank_pyxis.so

# Install Pyxis Slurm plugin
logger -s "Installing Pyxis Slurm plugin"
mkdir -p /usr/lib64/slurm
cp -fv ${SHARED_DIR}/spank_pyxis.so /usr/lib64/slurm
chmod +x /usr/lib64/slurm/spank_pyxis.so

logger -s "Install plugstack"
install_plugstack

logger -s "Pyxis installation complete"
