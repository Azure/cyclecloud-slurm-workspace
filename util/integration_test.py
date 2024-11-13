import json
import os
import pytest
import subprocess
import sys
import tempfile
import time
from typing import List, Optional


def _check_output(args: List[str]) -> str:

    print("Running", " ".join(args))
    return subprocess.check_output(args).decode()


DEPLOYMENT_CACHE = {}


def fetch_deployment(existing_rg: str) -> object:
    if existing_rg not in DEPLOYMENT_CACHE:
        raw_output = _check_output(
            [
                "az",
                "deployment",
                "group",
                "show",
                "-g",
                existing_rg,
                "-n",
                "pid-8d5b25bd-0ba7-49b9-90b3-3472bc08443e-partnercenter",
            ]
        )
        try:
            DEPLOYMENT_CACHE[existing_rg] = json.loads(raw_output)
        except:
            print("The following could not be parsed", file=sys.stderr)
            print(raw_output, file=sys.stderr)
            print("END", file=sys.stderr)
            raise

        json.dump(DEPLOYMENT_CACHE[existing_rg], sys.stderr, indent=2)
    return DEPLOYMENT_CACHE[existing_rg]


RESOURCE_GROUPS_TO_DELETE = []


def create_deployment(
    rg: str,
    location: str,
    branch: str,
    params: object,
    cc_vm_size: Optional[str] = None,
    execute_vm_size: Optional[str] = None,
    customization_scripts: Optional[list[str]] = None,
    customization_config: Optional[str] = None,
) -> object:
    if rg not in RESOURCE_GROUPS_TO_DELETE:
        RESOURCE_GROUPS_TO_DELETE.append(rg)
    fd, params_name = tempfile.mkstemp()
    print("Full params", params_name)
    json.dump(params, sys.stdout, indent=2)
    with os.fdopen(fd, "w") as fw:
        json.dump(params, fw, indent=2)
    args = [
        "python3",
        "util/deploy_sandbox_params.py",
        "-j",
        params_name,
        "-l",
        location,
        "-r",
        rg,
        "-b",
        branch,
    ]

    if execute_vm_size:
        args.extend(["-e", execute_vm_size])

    if cc_vm_size:
        args.extend(["-v", cc_vm_size])

    # for customization_script in customization_scripts or []:
    #     args.extend(["-s", customization_script])

    # if customization_config:
    #     args.extend(["-c", customization_config])

    try:
        print(_check_output(args))
        return fetch_deployment(rg)
    except:
        json.dump(params, sys.stderr, indent=2)
        raise


def create_or_get_deployment_from_config(
    config: dict,
    param_file_name: str,
    customization_scripts: Optional[list[str]] = None,
    customization_config: str = "util/integration/customization_config.json",
    infra: object = {},
    resource_group: Optional[str] = None,
    params_override: dict = {},
) -> object:
    try:
        rg = resource_group or (config["rg-prefix"] + param_file_name)
        return fetch_deployment(rg)
    except:
        return create_deployment_from_config(
            config,
            param_file_name,
            customization_scripts,
            customization_config,
            infra,
            resource_group=resource_group,
            params_override=params_override,
        )


def create_deployment_from_config(
    config: dict,
    param_file_name: str,
    customization_scripts: Optional[list[str]] = None,
    customization_config: str = "util/integration/customization_config.json",
    infra: object = {},
    resource_group: Optional[str] = None,
    params_override: dict = {},
) -> object:
    customization_scripts = (
        ["util/integration/run_tests.sh"]
        if customization_scripts is None
        else customization_scripts
    )
    params = read_params(param_file_name, config, infra)
    params.update(params_override)
    return create_deployment(
        resource_group or (config["rg-prefix"] + param_file_name),
        config["location"],
        config["branch"],
        params,
        config.get("cc_vm_size"),
        config.get("execute_vm_size"),
        customization_scripts,
        customization_config,
    )


# TODO tags


def read_params(name: str, config: dict, infra: object = {}) -> object:
    with open("util/integration/" + name + ".json") as fr:
        params = json.load(fr)

    with open("uidefinitions/createUiDefinition.json") as fr:
        ui = json.load(fr)["parameters"]

    def find(items: list, attr: str, value: str) -> dict:
        assert isinstance(items, list)
        if items and attr not in items[0]:
            raise RuntimeError(f"{attr} not found in {items[0].keys()}")
        return [x for x in items if x[attr] == value][0]

    if "steps" not in ui:
        raise RuntimeError(f"steps not in {ui.keys()}")
    scheduler_step = find(ui["steps"], "name", "scheduler")
    sched_sec = find(scheduler_step["elements"], "name", "schedulerSection")
    sched_vm = find(sched_sec["elements"], "name", "vmsize")["recommendedSizes"][0]
    sched_image = find(sched_sec["elements"], "name", "ImageName")
    default_value = sched_image["defaultValue"]
    image = find(sched_image["constraints"]["allowedValues"], "label", default_value)[
        "value"
    ]

    # make sure that we are using the latest images
    assert params["schedulerNode"]["value"]["image"] == image

    if "clusterName" not in params:
        params["clusterName"] = {"value": "ccw"}

    # make sure dev cleaned up params
    for key in [
        "adminSshPublicKey",
        "adminPassword",
        "location",
        "resourceGroup",
        "slurmSettings",
    ]:
        assert key not in params

    # pull in secure params
    params["adminSshPublicKey"] = {"value": config["adminSshPublicKey"]}
    params["adminPassword"] = {"value": config["adminPassword"]}
    params["startCluster"] = {"value": False}
    if config.get("bastion") is False:
        params["network"]["value"]["bastion"] = False

    if params["network"]["value"]["type"] == "existing" and infra:
        print("RDH UPDATING PARAMS", infra.keys())
        params["network"]["value"]["id"] = infra["vnet"]["value"]["id"]
    else:
        print("RDH leaving params alone", len(infra))
    return params


@pytest.fixture
def infra(config: dict) -> object:
    try:
        infra_rg = config.get("infra", config["rg-prefix"] + "infra-no-filers")
        return fetch_deployment(infra_rg)["properties"]["outputs"]
    except:
        return create_deployment_from_config(config, "infra-no-filers")


@pytest.fixture
def config() -> dict:
    print("config")
    with open("util/integration_test.json") as fr:
        return json.load(fr)


def test_existing_network_builtin(infra: object, config: dict) -> None:
    create_deployment_from_config(
        config, "enet-builtin", customization_scripts=None, infra=infra
    )


def test_existing_network_anf_aml(infra: object, config: dict) -> None:
    create_deployment_from_config(config, "enet-anf-aml", infra=infra)


def test_existing_network_anf_aml(infra: object, config: dict) -> None:
    create_deployment_from_config(config, "enet-anf-anf", infra=infra)


def test_ood(infra: object, config: dict) -> None:
     create_deployment_from_config(config, "enet-ood", infra=infra)


def _az_json(*args: str) -> object:
    raw = _check_output(list(args) + ["-o", "json"])
    return json.loads(raw)


# def test_cluster_name() -> None:
#     assert (
#         False
#     ), "Add test to exclude spaces etc and make sure the regex are the same in the ui and bicep"


def _delete_resources(resource_group: str) -> None:
    attempts = 90
    print("Deleting all resources under", resource_group)
    print(
        "Expect failed deletions, as we are not deleting these resources in dependency order."
    )
    print(
        "i.e. we may delete a NIC before deleting the VM, but eventually this will succeed"
    )
    while attempts > 0:
        attempts -= 1
        failures = []
        az_resp = _az_json("az", "resource", "list", "-g", resource_group)
        types = set([x["type"] for x in az_resp])
        for rname, rtype in [(x["name"], x["type"]) for x in az_resp]:
            try:
                _az_json(
                    "az",
                    "resource",
                    "delete",
                    "-g",
                    resource_group,
                    "--resource-type",
                    rtype,
                    "-n",
                    rname,
                )
            except:
                failures.append((rname, rtype))

        if failures:
            print("Waiting on", failures)
            time.sleep(10)
        else:
            print("All resources are deleting")
            break

    attempts = 90
    while attempts > 0:
        attempts -= 1
        response = _az_json("az", "resource", "list", "-g", resource_group)
        if response:
            print(
                "Waiting for the following to delete:",
                ",".join([x["name"] for x in response]),
            )
            time.sleep(10)
        else:
            print("All resources are deleted")
            break


def test_deploy_same_rg(infra: object, config: dict) -> None:
    rg = config["rg-prefix"] + "deploy-same-rg"
    _test_rg_reuse(delete_rg=False, infra=infra, config=config, rg=rg)


def test_deploy_same_rg_name(infra: object, config: dict) -> None:
    rg = config["rg-prefix"] + "deploy-same-rg-name"
    _test_rg_reuse(delete_rg=True, infra=infra, config=config, rg=rg)


"""
We have two use cases, and they are pretty similar - delete the RG or delete the resources in the
resource group without recreating it. In the former, we need to recreate the RG to get the guid generated
names, delete the role assignments, then delete the RG. In the latter, we simply delete the deployments.
"""
def _test_rg_reuse(delete_rg: bool, infra: object, config: dict, rg: str) -> None:
    location = config["location"]
    def _do_deployment(force: bool = False) -> object:
        create_func = create_or_get_deployment_from_config if force else create_deployment_from_config
        return create_func(
            config,
            "enet-builtin",
            customization_scripts=[],
            infra=infra,
            resource_group=rg,
            params_override={"startCluster": {"value": False}},
        )


    def _do_cleanup(delete_rg: bool):
        if delete_rg:
            try:
                _az_json("az", "group", "show", "-g", rg)
                subprocess.check_call(["az", "group", "delete", "-g", rg, "-y"])
            except:
                pass
        else:
            _delete_resources(rg)
        
        print("Running cleanup script...")
        args = ["util/delete_roles.sh", "--location", location, "--resource-group", rg]
        if delete_rg:
            args.append("--delete-resource-group")
        
        subprocess.check_call([args])
        print("Done cleanup script")

        try:
            _az_json("az", "group", "show", "-n", rg)
            assert not delete_rg, "resource group should have been deleted!"
        except subprocess.CalledProcessError:
            assert delete_rg, "resource group should NOT have been deleted!"
    
    # ensure we are in a clean state
    _do_cleanup(delete_rg=True)

    # deploy the rg
    _do_deployment(force=False)

    # either delete the resources or the rg
    _do_cleanup(delete_rg=delete_rg)

    # redeployments caused the issue - do not use get here
    _do_deployment(force=True)

    # actually clean it up
    _do_cleanup(delete_rg=True)
