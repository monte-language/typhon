#!/usr/bin/env nix-shell
#! nix-shell -i bash -p pypy libuv
inputs=($nativeBuildInputs)
libuv=${inputs[1]}
TYPHON_INCLUDE_PATH=$libuv/include TYPHON_LIBRARY_PATH=$libuv/lib PYTHONPATH=pypy:. pypy main.py -l mast repl.ty
