import json
import re
from pathlib import Path

import pytest


def _load_rg_regex() -> str:
    """Return the resource group name regex from createUiDefinition.json."""
    path = Path(__file__).resolve().parent.parent / "uidefinitions" / "createUiDefinition.json"
    with path.open() as f:
        data = json.load(f)

    for entry in data.get("parameters", {}).get("basics", []):
        if isinstance(entry, dict) and entry.get("name") == "rgNew":
            validations = entry.get("constraints", {}).get("validations", [])
            if validations:
                return validations[0].get("regex")
    raise KeyError("rgNew validation regex not found in createUiDefinition.json")


def test_rg_regex_allows_valid_names():
    pattern = re.compile(_load_rg_regex())
    valid = [
        "rg1",
        ".rg",
        "rg_1",
        "rg-1",
        "rg.name",
        "r",
        "a" * 89,
    ]
    for value in valid:
        assert pattern.fullmatch(value), f"expected regex to accept valid name: {value!r}"


def test_rg_regex_rejects_invalid_names():
    pattern = re.compile(_load_rg_regex())
    invalid = [
        "",  # empty
        "rg.",  # trailing period
        "rg ",  # space not allowed
        "rg/1",  # slash not allowed
        "a" * 90,  # exceeds max length
    ]
    for value in invalid:
        assert not pattern.fullmatch(value), f"expected regex to reject invalid name: {value!r}"


def _load_vm_name_regexes() -> list[str]:
    """Return the list of VM name regexes from createUiDefinition.json."""
    path = Path(__file__).resolve().parent.parent / "uidefinitions" / "createUiDefinition.json"
    with path.open() as f:
        data = json.load(f)

    for entry in data.get("parameters", {}).get("basics", []):
        if isinstance(entry, dict) and entry.get("name") == "CycleCloudVmName":
            return [
                validation.get("regex")
                for validation in entry.get("constraints", {}).get("validations", [])
                if validation.get("regex")
            ]
    raise KeyError("CycleCloudVmName validation regexes not found in createUiDefinition.json")


def _vm_fullmatch(name: str) -> bool:
    """Check a VM name against all VM name regexes."""
    return all(re.fullmatch(regex, name) for regex in _load_vm_name_regexes())


def test_vm_name_regex_allows_valid_names():
    valid = [
        "a",
        "vm-01",
        "vm.name",
        "1",
        "a" * 64,
    ]
    for value in valid:
        assert _vm_fullmatch(value), f"expected VM regexes to accept valid name: {value!r}"


def test_vm_name_regex_rejects_invalid_names():
    invalid = [
        "",  # empty
        "a" * 65,  # exceeds 64 chars
        "vm_name",  # underscore not allowed
        "vm$",  # special character not allowed
        "vm/1",  # slash not allowed
        " vm",  # leading space not allowed
        "vm ",  # trailing space not allowed
        ".vm",  # leading period not allowed
        "-vm",  # leading dash not allowed
        "vm.",  # trailing period not allowed
        "vm-",  # trailing dash not allowed
    ]
    for value in invalid:
        assert not _vm_fullmatch(value), f"expected VM regexes to reject invalid name: {value!r}"


def _load_cluster_name_regexes() -> list[str]:
    """Return the list of cluster name regexes from createUiDefinition.json."""
    path = Path(__file__).resolve().parent.parent / "uidefinitions" / "createUiDefinition.json"
    with path.open() as f:
        data = json.load(f)

    for step in data.get("parameters", {}).get("steps", []):
        if step.get("name") == "scheduler":
            for element in step.get("elements", []):
                if element.get("name") == "clusterSettings":
                    for sub in element.get("elements", []):
                        if isinstance(sub, dict) and sub.get("name") == "clusterName":
                            return [
                                v.get("regex")
                                for v in sub.get("constraints", {}).get("validations", [])
                                if v.get("regex")
                            ]
    raise KeyError("clusterName validation regexes not found in createUiDefinition.json")


def _cluster_name_fullmatch(name: str) -> bool:
    """Check a cluster name against all cluster name regexes."""
    return all(re.fullmatch(regex, name) for regex in _load_cluster_name_regexes())


def test_cluster_name_regex_allows_valid_names():
    valid = [
        "abc",
        "cluster-1",
        "123",
        "ab-c",
        "a1-cluster-9z",
        "a" * 50,
    ]
    for value in valid:
        assert _cluster_name_fullmatch(value), f"expected cluster name regexes to accept: {value!r}"


def test_cluster_name_regex_rejects_invalid_names():
    invalid = [
        "",  # empty
        "ab",  # too short (min 3)
        "a",  # too short
        "cluster_name",  # underscore not allowed
        "cluster.name",  # period not allowed
        "my cluster",  # space not allowed
        "-cluster",  # leading dash not allowed
        "cluster-",  # trailing dash not allowed
        ".cluster",  # leading period not allowed
        "cluster.",  # trailing period not allowed
        "clus/ter",  # slash not allowed
        "Cluster",  # uppercase not allowed
        "a-b",  # second char is dash (first two must be alphanumeric)
        "a" * 51,  # exceeds max length of 50
    ]
    for value in invalid:
        assert not _cluster_name_fullmatch(value), f"expected cluster name regexes to reject: {value!r}"


def _load_ood_fqdn_regex() -> str:
    """Return the OOD FQDN/IP regex from createUiDefinition.json."""
    path = Path(__file__).resolve().parent.parent / "uidefinitions" / "createUiDefinition.json"
    with path.open() as f:
        data = json.load(f)

    ood_sections = next(
        (step for step in data.get("parameters", {}).get("steps", []) if step.get("name") == "ood"),
        None,
    )
    if not ood_sections:
        raise KeyError("ood step not found in createUiDefinition.json")

    elements = ood_sections.get("elements", [])[0].get("elements", []) if ood_sections.get("elements") else []
    for element in elements:
        if isinstance(element, dict) and element.get("name") == "fqdn":
            constraints = element.get("constraints", {})
            regex = constraints.get("regex")
            if regex:
                return regex
    raise KeyError("fqdn regex not found in createUiDefinition.json")


def test_ood_fqdn_regex_allows_expected_patterns():
    pattern = re.compile(_load_ood_fqdn_regex())
    valid = [
        "ood.contoso.com",
        "a.b.example.org",
        "foo-bar.example.co",
        "example.com",
        "192.168.0.1",
        "255.255.255.255",
    ]
    for value in valid:
        assert pattern.fullmatch(value), f"expected OOD fqdn regex to accept: {value!r}"


def test_ood_fqdn_regex_rejects_invalid_patterns():
    pattern = re.compile(_load_ood_fqdn_regex())
    invalid = [
        "",  # empty
        "example",  # missing TLD
        "-example.com",  # leading dash
        "example-.com",  # trailing dash in label
        "example..com",  # double dot
        "exa_mple.com",  # underscore not allowed
        "256.1.1.1",  # invalid IPv4 octet
        "1.2.3",  # incomplete IPv4
        "foo.bar/baz",  # slash not allowed
        "example.com ",  # trailing space
    ]
    for value in invalid:
        assert not pattern.fullmatch(value), f"expected OOD fqdn regex to reject: {value!r}"
