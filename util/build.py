"""
Utilities for the build process
"""
import argparse
import json


def set_default_branch(branch):
    print(f"Setting default branch to {branch}")
    with open("build/mainTemplate.json") as fr:
        mainTemplate = json.load(fr)
    
    mainTemplate["parameters"]["branch"] = {"type": "string", "defaultValue": branch}

    with open("build/mainTemplate.json", "w") as fw:
        json.dump(mainTemplate, fw, indent=2)


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


def main():
    parser = argparse.ArgumentParser(description="Utilities for the build process")
    parser.add_argument("--branch", required=True)
    args = parser.parse_args()
    set_default_branch(args.branch)
    disable_automatic_app_registration()


if __name__ == "__main__":
    main()