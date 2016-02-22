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
      # XXX shouldn't have to read the lockfile twice
      let scriptName = (builtins.fromJSON (builtins.readFile lockfile)).entrypoint;
      in
      nixpkgs.dockerTools.buildImage {
        name = name;
        tag = "latest";
        contents = montePackage lockfile;
        config = {
          Cmd = [ ("/bin/" + scriptName) ];
          WorkingDir = "/";
        };
      };
  };
in
  typhon
