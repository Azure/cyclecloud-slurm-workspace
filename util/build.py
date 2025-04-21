"""
Utilities for the build process
"""
import argparse
import bicep_typeless
import base64
import json
import os
import shutil
import subprocess


def set_default_branch(branch):
    print(f"Setting default branch to {branch}")
    with open("build/mainTemplate.json") as fr:
        mainTemplate = json.load(fr)
    
    mainTemplate["parameters"]["branch"] = {"type": "string", "defaultValue": branch}

    with open("build/mainTemplate.json", "w") as fw:
        json.dump(mainTemplate, fw, indent=2)


def base64_encode_files_to_load():
    encoded_dir = "bicep/files-to-load/encoded"
    os.makedirs(encoded_dir, exist_ok=True)
    for file in os.listdir("bicep/files-to-load"):
        path = os.path.join("bicep/files-to-load", file)
        if path.endswith(".base64") or not os.path.isfile(path):
            continue
        base64_path = os.path.join(encoded_dir, f"{file}.base64")
        with open(path, "rb") as fr:
            data = fr.read()
        with open(base64_path, "wb") as fw:
            b64data = base64.b64encode(data)
            fw.write(b64data)
        

def disable_automatic_app_registration():
    print("Disabling automatic app registration in the UI")
    with open("build/createUiDefinition.json") as fr:
        createUiDefinition = json.load(fr)
    
    steps = createUiDefinition["parameters"]["steps"]
    ood = [s for s in steps if s["name"] == "ood"][0]
    regApp = [e for e in ood["elements"][0]["elements"] if e["name"] == "registerEntraIDApp"][0]
    regApp["constraints"]["allowedValues"] = regApp["constraints"]["allowedValues"][1:]

    with open("build/createUiDefinition.json", "w") as fw:
        json.dump(createUiDefinition, fw, indent=2)


def create_build_dir(ui_defintion: str, build_dir: str) -> None:
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
    os.makedirs(build_dir)
    shutil.copyfile(ui_defintion, os.path.join(build_dir, "createUiDefinition.json"))


def run_bicep_build(build_dir):
    # AGB: Using absolute path to avoid issues with relative paths in az bicep commands
    subprocess.check_output(["az", "bicep", "build", "--file", f"{os.getcwd()}/bicep/mainTemplate.bicep", "--outdir", build_dir])


def main():
    parser = argparse.ArgumentParser(description="Utilities for the build process")
    sub_parsers = parser.add_subparsers(dest="command")
    build_parser = sub_parsers.add_parser("build", help="Build the project")

    build_parser.add_argument("--branch", required=True)
    build_parser.add_argument("--build-dir", required=True, help="Build the project")
    build_parser.add_argument("--ui-definition", required=True, help="Path to the UI definition file")
    
    sub_parsers.add_parser("base64", help="base64 encodes all files under bicep/files-to-load")
    
    args = parser.parse_args()

    if args.command == "build":
        create_build_dir(args.ui_definition, args.build_dir)
        base64_encode_files_to_load()
        bicep_typeless.run()
        run_bicep_build(args.build_dir)
        set_default_branch(args.branch)
        disable_automatic_app_registration()
    elif args.command == "base64":
        base64_encode_files_to_load()
    else:
        raise ValueError(f"Unknown command: {args.command}")


if __name__ == "__main__":
    main()