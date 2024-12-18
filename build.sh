#!/bin/bash
set -e
# This script builds the ARM template and UI definition for the marketplace solution

VERSION="2024.11.08"

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
cat > build_sh_python_tmp.py<<EOF
import json
with open("build/mainTemplate.json") as fr:
    mainTemplate = json.load(fr)
mainTemplate["parameters"]["branch"] = {"type": "string", "defaultValue": "$BRANCH"}
with open("build/mainTemplate.json", "w") as fw:
    json.dump(mainTemplate, fw, indent=2)
EOF
python3 build_sh_python_tmp.py
rm -f build_sh_python_tmp.py

echo "Creating zipfile"
pushd "$build_dir"
zip -j "${GIT_ROOT}/build.zip" ./*
popd

${THIS_DIR}/arm-ttk/arm-ttk/Test-AzTemplate.sh $build_dir # -Skip Parameter-Types-Should-Be-Consistent
