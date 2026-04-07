import json


def test_no_existing_if_in_name():
    """
    Read in build/mainTemplate.json and recurse the structure so that there are no dictionaries
    that have "existing": true and an if() call exists anywhere in the "name" field.
    """
    with open("build/mainTemplate.json") as f:
        template = json.load(f)

    def recurse(d):
        if isinstance(d, dict):
            if d.get("existing") is True and "name" in d and "if(" in d["name"]:
                raise ValueError(
                    f"Found a dictionary with existing: true and an if() call in the name field: {d}"
                )
            for v in d.values():
                recurse(v)
        elif isinstance(d, list):
            for item in d:
                recurse(item)

    recurse(template)
