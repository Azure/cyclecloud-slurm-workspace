#!/bin/bash
set -e

pushd bicep/files-to-load
python3 create_ccw_template.py
popd