#!/bin/bash
SHARED_DIR=/sched/pyxis

function link_plugstack() {
   [ ! -e /etc/slurm/plugstack.conf ] && ln -s /sched/plugstack.conf /etc/slurm/plugstack.conf
   [ ! -e /etc/slurm/plugstack.conf.d ] && ln -s /sched/plugstack.conf.d /etc/slurm/plugstack.conf.d
}
logger -s "Copy Pyxis library to /usr/lib64/slurm"
mkdir -p /usr/lib64/slurm
cp -v $SHARED_DIR/spank_pyxis.so /usr/lib64/slurm
chmod +x /usr/lib64/slurm/spank_pyxis.so

logger -s "Install plugstack"
link_plugstack
