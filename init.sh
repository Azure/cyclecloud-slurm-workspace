#!/bin/bash
set -e
cd $(dirname $0)/
PYTHONPATH=util python3 util/build.py base64
