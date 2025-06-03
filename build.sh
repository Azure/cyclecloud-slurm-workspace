#!/bin/bash
set -e
# This script builds the ARM template and UI definition for the marketplace solution
cd $(dirname $0)/
VERSION="2025.06.03"

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

GIT_ROOT=$(git rev-parse --show-toplevel)
if [ "$1" == "" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
else
  BRANCH=$1
fi
if [ "$BRANCH" == "HEAD" ]; then 
    echo "Please check this out as a branch. If this is a tag, create a local branch with the same name"
    echo "e.g. git checkout ${VERSION} -b ${VERSION}"
    exit 2
fi

# az deployment create --template-uri requires a json file. This ensures that we have a json file
# that matches what the current bicep file would generate. Note we remove the generator version, as this will
# give false positives in the diff
# AGB: Using absolute path to avoid issues with relative paths in az bicep commands
az bicep build -f $(pwd)/bicep/ood/oodEntraApp.bicep --stdout | jq -r 'del(.metadata._generator)' > bicep/ood/oodEntraApp.json
git diff --exit-code bicep/ood/oodEntraApp.json

# run tests 
pushd bicep-test
bicep test test.bicep
popd 

UI_DEFINITION=${GIT_ROOT}/uidefinitions/createUiDefinition.json

build_dir="${GIT_ROOT}/build"

PYTHONPATH=util/ python3 util/build.py build --branch $BRANCH --build-dir "$build_dir" --ui-definition "$UI_DEFINITION" 

# Check if base 64-encoded utility files used by install.sh are the same as the prior commit
git diff --exit-code bicep/files-to-load/encoded

echo "Creating zipfile"
pushd "$build_dir"
zip -j "${GIT_ROOT}/build.zip" ./*
popd

${THIS_DIR}/arm-ttk/arm-ttk/Test-AzTemplate.sh $build_dir # -Skip Parameter-Types-Should-Be-Consistent
