# Upgrading to M1

## Upgrade CycleCloud
ssh into the cyclecloud vm as `root`
```bash
curl https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/refs/heads/feature/scale_m1/scale_m1/upgrade_cyclecloud.sh | bash -
```

### Upgrade the cluster
In the CycleCloud cluster template under ~hpcadmin/ccw1/slurm_template.txt, make the following changes.
_Note_ All of the commands should be run as `hpcadmin`.

0) Confirm that `~hpcadmin/ccw1/slurm_template.txt` is the latest version of the template in use.
1) Make a backup of the slurm template and parameters.
```bash
cp ~/ccw1/slurm_template.txt ~/ccw1/slurm_template_$(date +%s).txt
cp ~/ccw1/slurm_params.json ~/ccw1/slurm_params_$(date +%s).json
```
2) Change `[[[cluster-init cyclecloud/slurm:*:4.0.0]]]` to `[[[cluster-init cyclecloud/slurm:*:4.0.2]]]` in `slurm_template.txt`
4) Change `[[[cluster-init cyclecloud/healthagent:*:1.0.2]]]` to `[[[cluster-init cyclecloud/slurm:*:1.0.3]]]` in `slurm_template.txt`
5) Export and update the parameters. Note this will update the monitoring project to 1.0.2 and increase the BootDiskSize to 1024GB

**NOTE** Edit IMAGE_NAME below with the new GB200 image.
```bash
curl https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/refs/heads/feature/scale_m1/scale_m1/update_params.py > update_params.py
IMAGE_NAME=# Enter image name here
cyclecloud export_parameters ccw1 | python3 update_params.py $IMAGE_NAME > ~/ccw1/slurm_params.json
```
6) Re-import the cluster.
```bash
cyclecloud import_cluster ccw1 -f ~/ccw1/slurm_template.txt -p ~/ccw1/slurm_params.json -c Slurm --force
```


## Upgrade the Scheduler
ssh into the scheduler vm, and log in as `root`
```bash
curl https://raw.githubusercontent.com/Azure/cyclecloud-slurm-workspace/refs/heads/feature/scale_m1/scale_m1/upgrade_slurmctld.sh | bash -
```
This script makes the folowing changes:
1) Writes a new health agent to `/sched/ccw1/healthagent`.
2) Installs `/opt/cycle/capture_log.sh` on the scheduler node.
3) Installs updated imex_epilog.sh to `/sched/ccw1/epilog.d`.
4) Installs updated imex_epilog.sh to `/sched/ccw1/prolog.d`.
5) Installs `/opt/azurehpc/slurm/start_services.sh`.

The scheduler daemons will be up the whole time, but the partitions will be marked DOWN for a short period - on the order of 1 minute - while the upgrade is performed. Jobs can still be submitted to these partitions but new jobs will not be started. **The slurm configuration will not be changed.**


# Scaling M1

## scale_m1 command
The `scale_m1` command is installed at `/root/bin/scale_m1`. All of the following commands are assumed to be run as `root`. THere is a log for these commands at `/opt/azurehpc/slurm/logs/scale_m1.log`.

## Creating a reservation
```bash
scale_m1 create_reservation -p gpu
```
This will create a reservation called `scale_m1` in slurm. It will include all nodes that are not currently running jobs.

_NOTE_ This command will put the `gpu` partition into a `DOWN` state for approximately 15 seconds, before returning it to an `UP` state. The `DOWN` state will prevent any new jobs from being scheduled on this partition, but users may continue to submit jobs during this time. This is done simply so that `scale_m1` can avoid race conditions as it queries for idle nodes and then reserves them. These nodes will include nodes in `POWERED_UP` and `POWERED_DOWN` states.

This reservation can be edited via `scontrol update ReservationName=scale_m1` if any nodes need to be added or removed. This reservation will not be deleted by `scale_m1` so it is required that the user deletes this reservation / removes nodes from this reservation when they are ready for the nodes to run jobs.

## Powering up nodes
```bash
scale_m1 power_up --target-count 504 --overprovision 100
```
Interconnect Groups M1 requires that all VMSS requests are a multiple of 18. So if there are 10 nodes powered up in a drained state, and the above command is given, the result would be round_up_to_18(10 + 504 + 100) = 630 (15 racks of 18).

Note that if the target count was not reached, you can try a higher overprovision argument until we get to the target count.

## Pruning nodes
```bash
scale_m1 prune --target-count 504 > nodes_to_terminate.txt
```
`scale_m1 prune` writes out a suggestion of which nodes to terminate to get down to the specificed target count. This command does a few things.
1) Generates a topology file to $(realpath /etc/slurm/topology.conf).pre-pruning - i.e. `/sched/ccw1/topology.conf.pre-pruning`.
2) Using the topology in topology.conf.pre-pruning, nodes are then selected from the smallest blocks until the target count is reached.
3) Lastly, it writes to STDOUT the shorted node list of which nodes to terminate, i.e. `ccw1-gpu-[1,5,10-20]`

_Note_ we will only suggest nodes to terminate that we have in our reservation, so the end result may be suboptimal based on nodes that are running short jobs, for example, in a single rack, that we cannot terminate.

## Manually pruning and reconfiguring
Picking the right nodes to terminate is not something you typically want completely automated, so we recommend doing the following.
1) Use the prune command to generate a list of nodes to terminate.
```bash
scale_m1 prune -p gpu > nodes_to_terminate.txt
```
2) Confirm the nodes to terminate by looking at `/sched/ccw1/topology.conf.pre-pruning` and the current state of the cluster. Again, note that we can not guarantee an optimal selection.
3) run `scontrol update nodename=NODES_TO_TERMINATE state=power_down`
4) There is a delay between sending the power_down command and Slurm actually changing the state. Wait until `sinfo -n NODES_TO_TERMINATE -t powering_down,powered_down` shows that all of the nodes have at least entered the powering_down state, i.e. the state ends with `%` like `idle%`
5) run `azslurm topology -n -p gpu > new_topology.conf`. Confirm that this new file is correct, then `cp new_topology.conf $(realpath /etc/slurm/topology.conf)`
5) run `scontrol recoconfigure` so that the new topology is loaded.
6) run `scontrol show topology` to confirm it has taken effect.
7) Either delete the reservation via `scontrol delete reservationname=scale_m1` or begin removing nodes from it via `scontrol update rservationname=scale_m1 nodes=NEW_SET_OF_NODES` to allow jobs to run on these nodes.

## Automatic pruning and reconfiguring
```bash
scale_m1 prune_now --target-count 504
```
We can also do this automatically for you, however there is no opportunity to override which nodes we choose to terminate. *On a cluster running jobs, or when the reservation does not include all relevant nodes, this is NOT recommended.* However, on an empty cluster, this command will safely only terminate nodes in the smallest block sizes.
