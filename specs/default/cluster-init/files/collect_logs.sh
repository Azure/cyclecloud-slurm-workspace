#!/bin/bash
cluster_name=$( jetpack config cyclecloud.cluster.name )
set -e

if [ -z "$cluster_name" ]; then
  cluster_name="ccw"
fi

# Set the path to store the logs on /sched
vm_name=$(hostname)
path="/shared/$cluster_name/node_logs/$vm_name"

# User may optionally override default path
while (( "$#" )); do
  case $1 in
    --path)
      if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
        path="$2"
        shift 2
      else
        echo "Error: --path requires a non-empty option argument."
        exit 1
      fi
      ;;
    *)
      echo "Error: Invalid argument. Use --path"
      exit 1
      ;;
  esac
done

# Remove any trailing / in given path
path="${path%/}"

source_dir="/opt/azurehpc/diagnostics"

# Check if the diagnostics script is available (i.e., if node is using an AzureHPC image)
if [ -d "$source_dir" ]; then
  # Run the built-in script to gather diagnostics
  yes | bash "$source_dir"/gather_azhpc_vm_diagnostics.sh

  # Identify the log file created by the above script
  log_file_name=$(ls -t "$source_dir" | head -n 1 | sed 's/\.tar\.gz$//')
else
  # Create log file name in the same manner as diagnostics script if using a custom VM image
  vm_id=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-03-01&format=text")
  timestamp=$(date -u +"%Y-%m-%d.UTC%H.%M.%S")
  log_file_name="$vm_id"."$timestamp"
fi
# Move datetime to the beginning of the file name 
final_log_file_name=$(echo "$log_file_name" | sed -E 's/^([^.]+)\.(.+)$/\2.\1/')

# Create a temporary directory to store the logs before packaging them
tmp_dir="/tmp/logs"
mkdir -p "$tmp_dir" && cd "$tmp_dir"

if [ -d "$source_dir" ]; then 
  # Move the log archive to the temporary directory and extract it
  mv "$source_dir"/"$log_file_name".tar.gz .
  tar -xzf "$log_file_name".tar.gz && rm "$log_file_name".tar.gz
else
  # Create empty directory in which to store the node logs
  mkdir -p "$log_file_name"
fi

# Create a subdirectory named "cluster" and add more logs to it
cd "$log_file_name" && mkdir -p cluster && cd cluster
set +e # in a failed node, some of these directories may not exist
log_directories=(
    "/var/log/slurmd"
    "/opt/azurehpc/slurm/logs"
    "/opt/cycle/jetpack/logs"
)
for dir in "${log_directories[@]}"; do
  cp -a --parents "$dir" .
done
which scontrol && scontrol show config > slurm_config.txt
which scontrol && scontrol show nodes > slurm_nodes.txt
set -e

# Re-package the logs into an archive at the path specified by the user and clean up
cd ../..
mkdir -p "$path"
tar -czvf "$path"/"$final_log_file_name".tar.gz "$log_file_name" && rm -rf "$log_file_name"
rm -rf "$tmp_dir"
echo "Log archive created at $path/$final_log_file_name.tar.gz"