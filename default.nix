{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  typhon = with nixpkgs; rec {
    typhonVm_O2 = callPackage ./nix/vm.nix { buildJIT = false; };
    typhonVm = callPackage ./nix/vm.nix { buildJIT = true; };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
    bench = callPackage ./nix/bench.nix { typhonVm = typhonVm; mast = mast; };

    montePackage = s @ { name, version, ... }: let stuff = {
      name = "monte-${name}-${version}";
      buildInputs = [ typhonVm mast ];
      doCheck = false;
    }; in nixpkgs.stdenv.mkDerivation (s // stuff);
  };
in
  typhon
