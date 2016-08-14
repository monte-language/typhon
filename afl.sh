#!/bin/sh
set -x
set -eu

nix-env -i afl
nix-build -A typhonDumpMAST
[[ -d testcases ]] || mkdir testcases
[[ -d broken ]] || mkdir broken
afl-fuzz -i testcases -o broken result/bin/mt-dump-mast @@
