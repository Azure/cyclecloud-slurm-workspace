#!/bin/bash
set -e
if [ "$1" == "" ] || [ "$1" == "-h" ]; then
    echo $0 YYYY.MM.DD
    exit 1
fi

validate_slurm_version() {
    # Make sure that cyclecloud-slurm has set the latest release as GA.
    LATEST_SLURM_RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/Azure/cyclecloud-slurm/releases | jq -e '.[0]')
    SLURM_RELEASE_TAG=$(echo "$LATEST_SLURM_RELEASE_JSON" | jq -er '.tag_name')
    IS_PRERELEASE=$(echo "$LATEST_SLURM_RELEASE_JSON" | jq -r '.prerelease')
    IS_DRAFT=$(echo "$LATEST_SLURM_RELEASE_JSON" | jq -r '.draft')
    if [ "$IS_PRERELEASE" != "false" ] || [ "$IS_DRAFT" != "false" ]; then
        echo "Latest cyclecloud-slurm release is not GA. tag=$SLURM_RELEASE_TAG prerelease=$IS_PRERELEASE draft=$IS_DRAFT"
        exit 1
    fi

    # Now make sure that our default Slurm version matches the latest cyclecloud-slurm release.
    EXPECTED_SLURM_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/Azure/cyclecloud-slurm/$SLURM_RELEASE_TAG/templates/slurm.txt" | awk '/parameter configuration_slurm_version/{in_param=1} in_param && /DefaultValue/{gsub(/"/, "", $3); print $3; exit}')
    ACTUAL_SLURM_VERSION=$(jq -er 'first(.. | objects | select(.name? == "slurmVersion" and .type? == "Microsoft.Common.DropDown") | .defaultValue)' uidefinitions/createUiDefinition.json)
    if [ "$EXPECTED_SLURM_VERSION" != "$ACTUAL_SLURM_VERSION" ]; then
        echo "Expected Slurm version $EXPECTED_SLURM_VERSION from cyclecloud-slurm tag $SLURM_RELEASE_TAG does not match actual Slurm version $ACTUAL_SLURM_VERSION in createUiDefinition.json"
        exit 1
    fi
    grep -q "$EXPECTED_SLURM_VERSION" bicep/files-to-load/initial_params.json || (echo "Expected Slurm version $EXPECTED_SLURM_VERSION does not match actual Slurm version in bicep/files-to-load/initial_params.json"; exit 1)
}

validate_slurm_version

version=$1
git fetch origin --tags --force
git checkout $version
grep -F -q $version uidefinitions/createUiDefinition.json || (echo add $version to uidefinitions/createUiDefinition.json; exit 1)
grep "param projectVersion" bicep/mainTemplate.bicep | grep -F -q $version || (echo set project_version = $version in bicep/mainTemplate.bicep)
grep -F -q $version project.ini || (echo add $version to project.ini; exit 1)
./build.sh $version
