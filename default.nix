{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system };
  jobs = with nixpkgs; rec {
    typhonVm_O2 = callPackage ./nix/vm.nix { buildJIT = false; };
    typhonVm = callPackage ./nix/vm.nix { buildJIT = true; };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
  };
in
  jobs
