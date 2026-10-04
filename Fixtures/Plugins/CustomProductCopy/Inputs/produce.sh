#!/bin/sh
set -eu

source=$1
output=$2
mkdir -p "$(dirname "$output")"
xcrun clang -g -c "$source" -o "$output.o"
xcrun ar crs "$output" "$output.o"
