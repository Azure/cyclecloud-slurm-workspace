#!/bin/bash
set -e
if [ "$1" == "" ] || [ "$1" == "-h" ]; then
    echo $0 YYYY.MM.DD
    exit 1
fi

version=$1
git fetch origin --tags --force
git checkout $version
grep -F -q $version uidefinitions/createUiDefinition.json || (echo add $version to uidefinitions/createUiDefinition.json; exit 1)
grep "param projectVersion" bicep/mainTemplate.bicep | grep -F -q $version || (echo set project_version = $version in bicep/mainTemplate.bicep)
grep -F -q $version project.ini || (echo add $version to project.ini; exit 1)
./build.sh $version
