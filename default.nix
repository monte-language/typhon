{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  typhon = with nixpkgs; rec {
    typhonVm_O2 = callPackage ./nix/vm.nix { buildJIT = false; };
    typhonVm = callPackage ./nix/vm.nix { buildJIT = true; };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
    bench = callPackage ./nix/bench.nix { typhonVm = typhonVm; mast = mast; };
    mt = callPackage ./nix/mt.nix { typhonVm = typhonVm; mast = mast; };
    montePackage = callPackage ./nix/montePackage.nix { typhonVm = typhonVm; mast = mast; };
    dockerize = {lockfile, name}:
      let
        # Decode the lockfile once, and use it multiple times.
        lockSet = builtins.fromJSON (builtins.readFile lockfile);
        scriptName = lockSet.entrypoint;
      in
        nixpkgs.dockerTools.buildImage {
          name = name;
          tag = "latest";
          contents = montePackage lockSet;
          config = {
            Cmd = [ ("/bin/" + scriptName) ];
            WorkingDir = "/";
          };
        };
  };
in
  typhon
