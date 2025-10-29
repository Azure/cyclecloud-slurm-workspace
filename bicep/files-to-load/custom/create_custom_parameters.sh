#!/bin/bash 

# Argument 1: Path to the filled-out cluster parameters file for the default Slurm template (JSON)
# Argument 2: Path to the deployment outputs JSON file
# Output: Fully-formed custom parameters file to stdout

# Trivial example: The below outputs the default cluster parameters file without modifications
cat $1