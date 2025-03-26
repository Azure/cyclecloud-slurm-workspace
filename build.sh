#!/bin/bash
set -e
# This script builds the ARM template and UI definition for the marketplace solution

VERSION="2026.03.26"

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
az bicep build -f bicep/ood/oodEntraApp.bicep --stdout | jq -r 'del(.metadata._generator.version)' > bicep/ood/oodEntraApp.json
git diff --exit-code bicep/ood/oodEntraApp.json

UI_DEFINITION=${GIT_ROOT}/uidefinitions/createUiDefinition.json

build_dir="${GIT_ROOT}/build"
rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "Copying UI definition"
cp "$UI_DEFINITION" "$build_dir"
python3 bicep-typeless.py

echo "Converting Bicep to ARM template"
az bicep build --file "${GIT_ROOT}/bicep-typeless/mainTemplate.bicep" --outdir "$build_dir"
rm -rf bicep-typeless

echo Adding branch=$BRANCH to build/mainTemplate.json
python3 util/build.py --branch $BRANCH

echo "Creating zipfile"
pushd "$build_dir"
zip -j "${GIT_ROOT}/build.zip" ./*
popd

${THIS_DIR}/arm-ttk/arm-ttk/Test-AzTemplate.sh $build_dir # -Skip Parameter-Types-Should-Be-Consistent
