#!/bin/bash
# Library of functions to be used across scripts
read_os()
{
    os_release=$(cat /etc/os-release | grep "^ID\=" | cut -d'=' -f 2 | xargs)
    os_version=$(cat /etc/os-release | grep "^VERSION_ID\=" | cut -d'=' -f 2 | xargs)
}

function is_scheduler() {
    jetpack config slurm.role | grep -q 'scheduler'
}

function is_login() {
    jetpack config slurm.role | grep -q 'login'
}

function is_compute() {
    jetpack config slurm.role | grep -q 'execute'
}
