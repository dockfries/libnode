#!/bin/bash
set -ex

choco install nasm
. "$(dirname "$0")"/prepare-env.sh
cd ./node

./vcbuild.bat release dll package x86

mv ./out/Release/node-${NODE_VERSION}-win-x86 "${OUTPUT_PREFIX}/"
cp ./LICENSE "${OUTPUT_PREFIX}/LICENSE"
