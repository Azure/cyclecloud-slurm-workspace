import json, sys
"""
Usage: cyclecloud export_parameters ccw1 | python3 update_params.py > slurm_params.json

This script will upgrade the monitoring project to 1.0.2 and increase the BootDiskSize to 1024 GB.
"""

data = json.load(sys.stdin)

for x in data:
    if "ClusterInitSpecs" in x and data.get(x):
        monitoring = data[x].pop("monitoring:default:1.0.1")
        monitoring["Name"] = "monitoring:default:1.0.2"
        monitoring["Version"] = "1.0.2"
        data[x][monitoring["Name"]] = monitoring
    elif "BootDiskSize" == x:
        data[x] = 1024

json.dump(data, sys.stdout, indent=2)