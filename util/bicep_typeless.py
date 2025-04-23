import os
import shutil

"""
The partner center does note allow bicep v2 at the mainTemplate level. Unfortunately,
if we want to type check our parameters, then we need to propagate this type checking from
mainTemplate all the way down. This script simply strips all type checking.
"""

OUTPUT_ARRAY_TYPES = ["types.cluster_init_param_t","availabilityZone_t[]"]

def run() -> None:
    biceps = os.listdir("bicep")
    if os.path.exists("bicep-typeless"):
        shutil.rmtree("bicep-typeless")
    shutil.copytree("bicep", "bicep-typeless")

    for fil in biceps:
        if fil.endswith(".bicep"):
            process_bicep(f"bicep/{fil}", f"bicep-typeless/{fil}")


def process_param(line: str) -> str:
    toks = line.split()
    if toks[2] in OUTPUT_ARRAY_TYPES:
        toks[2] = "array"
    elif toks[2].endswith("_t"):
        toks[2] = "object"
    return " ".join(toks) + "\n"


def process_func(line: str) -> str:
    toks = line.split()
    for i in range(len(toks)):
        if toks[i].endswith("_t"):
            toks[i] = "object"
        if toks[i].endswith("_t)"):
            toks[i] = "object)"
    return " ".join(toks) + "\n"


def process_bicep(input_path: str, output_path: str) -> None:
    with open(input_path) as fr:
        lines = fr.readlines()
    
    with open(output_path, "w") as fw:
        for line in lines:
            if line.startswith("param") or line.startswith("output"):
                fw.write(process_param(line))
            elif line.startswith("import"):
                if "exports.bicep" in line:
                    fw.write(line)
                continue
            elif line.startswith("func "):
                fw.write(process_func(line))
            else:
                fw.write(line)

run()