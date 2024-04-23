#!/bin/bash
set -e
# This script builds the ARM template and UI definition for the azhop marketplace solution

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

GIT_ROOT=$(git rev-parse --show-toplevel)

UI_DEFINITION=${GIT_ROOT}/uidefinitions/createUiDefinition.json

build_dir="${GIT_ROOT}/build"
rm -rf "$build_dir"
mkdir -p "$build_dir"

echo "Copying UI definition"
cp "$UI_DEFINITION" "$build_dir"

echo "Converting Bicep to ARM template"
az bicep build --file "${GIT_ROOT}/bicep/mainTemplate.bicep" --outdir "$build_dir"

echo "Creating zipfile"
pushd "$build_dir"
zip -j "${GIT_ROOT}/build.zip" ./*
popd

#${THIS_DIR}/arm-ttk/arm-ttk/Test-AzTemplate.sh $build_dir # -Skip Parameter-Types-Should-Be-Consistent