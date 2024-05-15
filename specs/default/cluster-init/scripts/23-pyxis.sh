#!/bin/bash
set -e
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$script_dir/../files/common.sh" 

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
   echo 'required /usr/lib64/slurm/spank_pyxis.so runtime_path=/mnt/enroot/enroot-runtime' > /sched/plugstack.conf.d/pyxis.conf
   chown slurm:slurm /sched/plugstack.conf.d/pyxis.conf
}

function install_pyxis_library() {
   mkdir -p /usr/lib64/slurm
   cp -fv $SHARED_DIR/spank_pyxis.so /usr/lib64/slurm
   chmod +x /usr/lib64/slurm/spank_pyxis.so
}

function build_pyxis() {

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
}

if is_scheduler; then
   logger -s "Build Pyxis library"
   build_pyxis

   logger -s "Install plugstack"
   install_plugstack
fi

logger -s "Install Pyxis library"
install_pyxis_library

logger -s "Install plugstack"
link_plugstack

logger -s "Pyxis installation complete"
