import json, sys
"""
Usage: cyclecloud export_parameters ccw1 | python3 update_params.py > slurm_params.json

This script will upgrade the monitoring project to 1.0.2 and increase the BootDiskSize to 1024 GB.
"""


if len(sys.argv) < 2:
    print("Usage: python3 update_params.y image_name")
    sys.exit(1)

data = json.load(sys.stdin)

for x in data:
    if "ClusterInitSpecs" in x and data.get(x):
        for version in ["1.0.0", "1.0.1"]:
            key = f"monitoring:default:{version}"
            if key not in data[x]:
                continue
            monitoring = data[x].pop(key)
            monitoring["Name"] = "monitoring:default:1.0.2"
            monitoring["Version"] = "1.0.2"
            data[x][monitoring["Name"]] = monitoring
    elif "BootDiskSize" == x:
        data[x] = 1024
    elif "GPUImageName" == x:
        data[x] = sys.argv[1]

json.dump(data, sys.stdout, indent=2)