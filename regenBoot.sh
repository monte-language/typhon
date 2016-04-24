#!/bin/sh
set -eu
set -x
mast=$(nix-build -A mast)/mast
pushd boot
for path in **/*.mast; do
    cp -v $mast/$path $path
done
popd
