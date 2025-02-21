#!/bin/bash

# Script requirements:
#   nvme-cli
#   mdadm
#   gdisk
set -x
readonly USAGE="Usage: $(basename "$0") <filesystem> <filesystem mount point (optional)>"

# Label used to identify the NVMe array file system and associated disks
# Can't exceed 16 characters
readonly RAID0_FILESYSTEM_LABEL="azure_temp"
# Device path used for the RAID 0 NVMe array
# Choose any unoccupied device path of format /dev/mdX (X = 0 to 99)
readonly RAID0_DEVICE_PATH="/dev/md0"
# Formatted RAID 0 partition is mounted here
readonly DEFAULT_MOUNT_POINT="/mnt/${RAID0_FILESYSTEM_LABEL}"

filesystem="$1"
if [ ! "$filesystem" ]; then
    printf "No filesystem specified. Usage: $USAGE\n"
    exit 1
fi
if ! [ -x "$(command -v mkfs.$filesystem)" ]; then
    printf "Filesystem \"$filesystem\" not supported by mkfs\n$USAGE\n"
    exit 1
fi

mount_point="$2"
if [ ! "$mount_point" ]; then
    printf "No mount point specified. Using default: $DEFAULT_MOUNT_POINT\n"
    mount_point=$DEFAULT_MOUNT_POINT
fi

# Make sure mdadm.conf is present
mdadm_conf_path=""
if [ -e "/etc/mdadm/mdadm.conf" ]; then
    mdadm_conf_path="/etc/mdadm/mdadm.conf"
elif [ -e "/etc/mdadm.conf" ]; then
    mdadm_conf_path="/etc/mdadm.conf"
else
    print "Couldn't find mdadm.conf file"
    exit 1
fi

# Enumerate unmounted NVMe direct disks
devices=$(lsblk -p -o NAME,TYPE,MOUNTPOINT | grep "nvme" | awk '$2 == "disk" && $3 == "" {print $1}')
nvme_direct_disks=()
for device in $devices
do
    if nvme id-ctrl "$device" | grep -q "Microsoft NVMe Direct Disk"; then
        nvme_direct_disks+=("$device")
    fi
done
nvme_direct_disk_count=${#nvme_direct_disks[@]}
printf "Found $nvme_direct_disk_count NVMe Direct Disks\n"

# CCW MODIFICATION: Early exit if there are no nvme devices
# TODO this is added since we run this on every node. Ideally we would only
# run this on compute nodes that actually have nvme
if [ "$nvme_direct_disk_count" -eq 0 ]; then
    printf "No NVMe Direct Disks found\n"
    exit 0
fi

# Check if there's already an NVMe Direct Disk RAID 0 disk (or remnant data)
if grep "$RAID0_FILESYSTEM_LABEL" /etc/fstab > /dev/null; then
    fstab_entry_present=true
fi
if grep "$RAID0_FILESYSTEM_LABEL" $mdadm_conf_path > /dev/null; then
    mdadm_conf_entry_present=true
fi
if [ -e $RAID0_DEVICE_PATH ]; then
    nvme_raid0_present=true
fi
if [ "$fstab_entry_present" = true ] || [ "$mdadm_conf_entry_present" = true ] || [ "$nvme_raid0_present" = true ]; then
    # Check if the RAID 0 volume and associated configurations are still intact or need to be reinitialized
    #
    # If reinitialization is needed, clear the old RAID 0 information and associated files

    reinit_raid0=false
    if [ "$fstab_entry_present" = true ] && [ "$mdadm_conf_entry_present" = true ] && [ "$nvme_raid0_present" = true ]; then
        # Check RAID 0 device status
        if ! mdadm --detail --test $RAID0_DEVICE_PATH &> /dev/null; then
            reinit_raid0=true
        # Test the NVMe direct disks for valid mdadm superblocks
        else
            for device in "${nvme_direct_disks[@]}"
            do
                if ! mdadm --examine $device &> /dev/null; then
                    reinit_raid0=true
                    break
                fi
            done
        fi
    else
        reinit_raid0=true
    fi

    if [ "$reinit_raid0" = true ]; then
        echo "Errors found in NVMe RAID 0 temp array device or configuration. Reinitializing."

        # Remove the file system and partition table, and stop the RAID 0 array
        if [ "$nvme_raid0_present" = true ]; then
            if [ -e ${RAID0_DEVICE_PATH}p1 ]; then
                umount ${RAID0_DEVICE_PATH}p1
                wipefs -a -f ${RAID0_DEVICE_PATH}p1
            fi
            sgdisk -o $RAID0_DEVICE_PATH &> /dev/null
            mdadm --stop $RAID0_DEVICE_PATH
        fi

        # Remove any mdadm metadata from all NVMe Direct Disks
        for device in "${nvme_direct_disks[@]}"
        do
            printf "Clearing mdadm superblock from $device\n"
            mdadm --zero-superblock $device &> /dev/null
        done

        # Remove any associated entries in fstab and mdadm.conf
        sed -i.bak "/$RAID0_FILESYSTEM_LABEL/d" /etc/fstab
        sed -i.bak "/$RAID0_FILESYSTEM_LABEL/d" $mdadm_conf_path
    else
        printf "Valid NVMe RAID 0 array present and no additional Direct Disks found. Skipping\n"
        exit 0
    fi
fi

if [ "$nvme_direct_disk_count" -eq 0 ]; then
    printf "No NVMe Direct Disks found\n"
    exit 1
elif [ "$nvme_direct_disk_count" -eq 1 ]; then
    additional_mdadm_params="--force"
fi

# Initialize enumerated disks as RAID 0
printf "Creating RAID 0 array from:\n"
printf "${nvme_direct_disks[*]}\n\n"
if ! mdadm --create $RAID0_DEVICE_PATH --verbose $additional_mdadm_params --name=$RAID0_FILESYSTEM_LABEL --level=0 --raid-devices=$nvme_direct_disk_count ${nvme_direct_disks[*]}; then
    printf "Failed to create RAID 0 array\n"
    exit 1
fi

# Create a GPT partition entry
readonly GPT_PARTITION_TYPE_GUID="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
printf "\nCreating GPT on $RAID0_DEVICE_PATH..\n"
sgdisk -o $RAID0_DEVICE_PATH &> /dev/null
if ! sgdisk --new 1::0 --typecode 1:$GPT_PARTITION_TYPE_GUID $RAID0_DEVICE_PATH  &> /dev/null; then
    printf "Failed to create partition on $RAID0_DEVICE_PATH\n"
    exit 1
fi

# Format the partition
partition_path="${RAID0_DEVICE_PATH}p1"
printf "\nCreating $filesystem filesystem..\n"
if ! mkfs.$filesystem -q -L $RAID0_FILESYSTEM_LABEL $partition_path; then
    printf "Failed to create $filesystem filesystem\n"
    exit 1
fi
printf "The operation has completed successfully.\n"

# Add the partition to /etc/fstab
echo "LABEL=$RAID0_FILESYSTEM_LABEL $mount_point $filesystem defaults,nofail 0 0" >> /etc/fstab

# Add RAID 0 array to mdadm.conf
mdadm --detail --scan >> $mdadm_conf_path
update-initramfs -u

# Mount the partition
printf "\nMounting filesystem to $mount_point..\n"
mkdir $mount_point &> /dev/null
if ! mount -a; then
    printf "Failed to automount partition\n"
    exit 1
fi
printf "The operation has completed successfully.\n"

exit 0