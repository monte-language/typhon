{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./nix/vm.nix { buildJIT = false;
                                          libsodium = libsodium0; };
    typhonVmCrashy = callPackage ./nix/vm.nix { buildJIT = true; };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
    # XXX broken for unknown reasons
    # bench = callPackage ./nix/bench.nix { typhonVm = typhonVm; mast = mast; };
    mt = callPackage ./nix/mt.nix { typhonVm = typhonVm; mast = mast; };
    montePackage = callPackage ./nix/montePackage.nix { typhonVm = typhonVm;
                                                        mast = mast; };
    mtDocker = nixpkgs.dockerTools.buildImage {
        name = "monte";
        tag = "latest";
        contents = mt;
        config = {
            Cmd = [ "/bin/mt repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
