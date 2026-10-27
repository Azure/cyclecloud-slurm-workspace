#!/usr/bin/env python3
r"""Restore Open OnDemand cluster discovery for OOD clusters created with CycleCloud 8.10.

Run this script as root on the CycleCloud server using Python 3. The examples
assume you have copied it to /root/ood_discovery_reader.py, owned by root.

This script adds cluster read access to the OOD node's service account to
restore cluster discovery affected by a permissions change introduced in CycleCloud 8.10.
Use --remove if the additional access is no longer needed.


Grant discovery access
----------------------
Preview the changes first. --dry-run reads the server and prints proposed
changes without applying them:

  sudo python3 /root/ood_discovery_reader.py --dry-run

To apply the changes, run the same command without --dry-run:

  sudo python3 /root/ood_discovery_reader.py

A manual run grants discovery access once. Rerun after recreating OOD nodes or
accounts; adding scheduler clusters does not require another run.
Each run also removes this script's grants for clusters with no detected OOD
nodes. Review a dry-run before applying changes.

Scheduled runs
--------------
Unchanged runs are quiet by default. Add --verbose to see detected nodes and
completion messages; --dry-run still prints proposed changes without it.
If one cluster fails, the script logs the error and continues with the others,
then exits nonzero. Discovery failures stop the entire run without changes.

Example /etc/cron.d/ood-discovery-reader entry (one physical line):

  * * * * * root /usr/bin/python3 /root/ood_discovery_reader.py >> /var/log/ood-discovery-reader.log 2>&1

Configure log rotation and monitor the log for errors.

Remove discovery access
-----------------------
Stop any scheduled runs first. Preview removal with:

  sudo python3 /root/ood_discovery_reader.py --remove --dry-run

Then remove --dry-run to apply:

  sudo python3 /root/ood_discovery_reader.py --remove

Perform this cleanup when deleting the OOD cluster.
"""

import argparse
import fcntl
import json
import logging
import os
import signal
import subprocess
import sys


MANAGED_BY = "cyclecloud-ood-discovery-reader-v1"
LOCK_PATH = "/var/lock/cyclecloud-ood-discovery-reader.lock"


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def ad_list(values):
    return "{" + ", ".join(quote(value) for value in values) + "}"


def same_name(left, right):
    return isinstance(left, str) and left.casefold() == right.casefold()


def ood_user_filter(cluster, scopes):
    return (
        "ServiceAccount === true && ScopeCluster === {} && ScopeName in {}"
    ).format(quote(cluster), ad_list(scopes))


def signal_process_group(process, sig):
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass  # The entire process group has already exited.


def execute(args, statement, write=False):
    if write:
        logging.info("%s: %s", "DRY RUN" if args.dry_run else "APPLY", statement)
        if args.dry_run:
            return
    process = subprocess.Popen(
        [args.cycle_server, "execute", "--format", "json", statement],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=120)
    except subprocess.TimeoutExpired as error:
        signal_process_group(process, signal.SIGTERM)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            pass  # Escalate after the grace period.
        finally:
            # Kill remaining descendants even if the launcher and its pipes exited first.
            signal_process_group(process, signal.SIGKILL)
            process.communicate()
        raise RuntimeError(
            "cycle_server timed out after 120 seconds; its process group was terminated. "
            "Any datastore operation already submitted may still complete."
        ) from error
    if process.returncode:
        raise RuntimeError(
            "cycle_server exited with {}: {}".format(
                process.returncode, (stderr or stdout).strip()
            )
        )
    if stderr.strip():
        logging.warning("cycle_server: %s", stderr.strip())
    if not write:
        records = json.loads(stdout)
        if not isinstance(records, list) or any(not isinstance(row, dict) for row in records):
            raise RuntimeError("Expected a JSON array of records from cycle_server")
        return [{key.lower(): value for key, value in row.items()} for row in records]


def set_membership(args, user, role, granted, target):
    roles = user.get("roles")
    if roles is not None and (
        not isinstance(roles, list) or any(not isinstance(value, str) for value in roles)
    ):
        raise RuntimeError("Invalid Roles on user {!r}".format(user["name"]))
    existing = [] if roles is None else roles
    if any(same_name(value, role) for value in existing) == granted:
        return
    updated = existing + [role] if granted else [
        value for value in existing if not same_name(value, role)
    ]
    # SET evaluates atomically; WHERE only selects records before the modification.
    condition = "Roles === {}".format(
        "undefined" if roles is None else ad_list(roles)
    )
    if granted:
        condition += " && " + target
    execute(
        args,
        "UPDATE AuthenticatedUser SET Roles = ifThenElse({}, {}, Roles) "
        "WHERE Name === {}".format(condition, ad_list(updated), quote(user["name"])),
        write=True,
    )
    if args.dry_run:
        return
    current = execute(args, "SELECT Roles FROM AuthenticatedUser WHERE Name === {}".format(
        quote(user["name"])
    ))
    if not current and not granted:
        return
    current_roles = current[0].get("roles") if len(current) == 1 else None
    if not isinstance(current_roles, list) or (
        any(same_name(value, role) for value in current_roles) != granted
    ):
        raise RuntimeError(
            "Role update did not persist for {!r}; possible concurrent change. Rerun.".format(
                user["name"]
            )
        )


def reconcile(args, cluster, scopes):
    role = "OODDiscoveryReader-" + cluster
    permission = "OODDiscoveryRead-" + cluster
    definitions = [
        ("Application.Permission", permission,
         {"Operations": ["Read"], "ForTypes": ["Cloud.Cluster"]}),
        ("Application.Role", role, {"Allow": [permission]}),
    ]
    owned_filter = "OODDiscoveryManagedBy === {} && OODDiscoveryCluster === {}".format(
        quote(MANAGED_BY), quote(cluster)
    )
    existing = set()
    pending = []
    for record_type, name, attributes in definitions:
        attributes = dict(attributes, Hidden=True, OODDiscoveryManagedBy=MANAGED_BY,
                          OODDiscoveryCluster=cluster)
        values = {
            key: ad_list(value) if isinstance(value, list) else quote(value)
            for key, value in attributes.items()
        }
        matches = " && ".join("{} === {}".format(key, value) for key, value in values.items())
        records = execute(args,
            "SELECT OODDiscoveryManagedBy, OODDiscoveryCluster, ({}) AS DefinitionMatches "
            "FROM {} WHERE Name === {}".format(
                matches, record_type, quote(name)
            )
        )
        if records and (len(records) != 1 or not (
            same_name(records[0].get("ooddiscoverymanagedby"), MANAGED_BY)
            and same_name(records[0].get("ooddiscoverycluster"), cluster)
        )):
            raise RuntimeError("Refusing to modify unrelated record {!r}".format(name))
        if records:
            existing.add(record_type)
        if not records or records[0].get("definitionmatches") is not True:
            fields = " ".join("{} = {};".format(key, value) for key, value in values.items())
            pending.append("STORE [AdType = {}; Name = {}; {}]".format(
                quote(record_type), quote(name), fields
            ))

    removing = args.remove or not scopes
    target = ood_user_filter(cluster, scopes)
    users = execute(args,
        "SELECT Name, Roles, ScopeName, ({}) AS IsOOD FROM AuthenticatedUser "
        "WHERE ({} in Roles) || ({})".format(target, quote(role), target)
    )
    selected = [user for user in users if user.get("isood") is True]
    if not removing:
        for scope in scopes:
            matches = [user for user in selected if same_name(user.get("scopename"), scope)]
            if len(matches) > 1:
                raise RuntimeError("Multiple service users found for {} / {}".format(cluster, scope))
            if not matches:
                logging.warning("No service user yet for %s / %s; rerun later", cluster, scope)

    if removing:
        # Revoke access first, but retain the role's ownership metadata until cleanup succeeds.
        if "Application.Permission" in existing:
            execute(args, "DELETE FROM Application.Permission WHERE Name === {} && {}".format(
                quote(permission), owned_filter
            ), write=True)
        for user in users:
            set_membership(args, user, role, False, target)
        if "Application.Role" in existing:
            execute(args, "DELETE FROM Application.Role WHERE Name === {} && {}".format(
                quote(role), owned_filter
            ), write=True)
        logging.debug(
            "%s cleanup for %s (%s)",
            "Planned" if args.dry_run else "Completed", cluster,
            "explicit removal" if args.remove else "no OOD nodes detected",
        )
        return

    for user in users:
        if user.get("isood") is not True:
            set_membership(args, user, role, False, target)
    for statement in pending:
        execute(args, statement, write=True)
    for user in selected:
        set_membership(args, user, role, True, target)
    logging.debug(
        "%s %s for %d OOD service user(s)",
        "Planned" if args.dry_run else "Reconciled", role, len(selected),
    )


def discover(args):
    clusters = {}
    if not args.remove:
        live_clusters = execute(args,
            "SELECT ClusterName FROM Cloud.Cluster WHERE IsTemplate !== true"
        )
        live_names = {row["clustername"].casefold(): row["clustername"] for row in live_clusters}
        nodes = execute(args,
            "SELECT ClusterName, Name, Template, ClusterInitSpecs FROM Cloud.Node "
            "WHERE IsArray !== true && ClusterInitSpecs isnt undefined"
        )
        for node in nodes:
            cluster_name = node.get("clustername")
            if not isinstance(cluster_name, str) or cluster_name.casefold() not in live_names:
                continue
            specs = node.get("clusterinitspecs")
            if not isinstance(specs, dict):
                raise RuntimeError("Invalid ClusterInitSpecs on node {!r}".format(node.get("name")))
            uses_ood = False
            for spec in specs.values():
                if not isinstance(spec, dict):
                    raise RuntimeError("Invalid cluster-init spec on node {!r}".format(node.get("name")))
                spec = {key.lower(): value for key, value in spec.items()}
                uses_ood = uses_ood or same_name(spec.get("project"), "ood")
            if not uses_ood:
                continue
            # Array members use Template as their scope; standalone nodes use Name.
            scope = node.get("template") or node.get("name")
            if not isinstance(scope, str) or not scope.strip():
                raise RuntimeError("Cannot resolve OOD scope for node {!r}".format(node.get("name")))
            cluster = live_names[cluster_name.casefold()]
            scopes = clusters.setdefault(cluster.casefold(), (cluster, {}))[1]
            scopes[scope.casefold()] = scope
            logging.debug("Detected OOD node %s / %s (scope %s)", cluster, node.get("name"), scope)

    # Ownership metadata also finds grants whose clusters have been deleted.
    for record_type in ("Application.Permission", "Application.Role"):
        records = execute(args,
            "SELECT OODDiscoveryCluster FROM {} WHERE OODDiscoveryManagedBy === {}".format(
                record_type, quote(MANAGED_BY)
            )
        )
        for record in records:
            cluster = record.get("ooddiscoverycluster")
            if not isinstance(cluster, str) or not cluster.strip():
                raise RuntimeError("Owned {} record has no OODDiscoveryCluster".format(record_type))
            clusters.setdefault(cluster.casefold(), (cluster, {}))
    return clusters


def main():
    parser = argparse.ArgumentParser(
        description="Maintain an OOD role with read access to all clusters.",
        epilog="See the script's header for usage and rollback instructions.",
    )
    parser.add_argument("--cycle-server", default="/opt/cycle_server/cycle_server")
    parser.add_argument("--dry-run", action="store_true", help="Query and print changes only.")
    parser.add_argument("--verbose", action="store_true", help="Log discovery and completion details.")
    parser.add_argument("--remove", action="store_true", help="Remove all roles/permissions owned by this script.")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    failed = False
    try:
        if os.geteuid() != 0:
            raise RuntimeError("Run as root on the CycleCloud server, including for dry-run")
        with open(LOCK_PATH, "a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another invocation holds a lock: " + LOCK_PATH)
            clusters = discover(args)
            if not clusters:
                logging.debug("No OOD nodes or existing roles/permissions found")
            for cluster, scopes in clusters.values():
                try:
                    reconcile(args, cluster, sorted(scopes.values()))
                except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                    logging.error("Failed to reconcile cluster %s: %s", cluster, error)
                    failed = True
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        logging.error("%s", error)
        return 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
