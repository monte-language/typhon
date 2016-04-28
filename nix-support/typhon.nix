{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  libsodium0 = nixpkgs.libsodium.overrideDerivation (oldAttrs: {stripAllList = "lib";});
  typhon = with nixpkgs; rec {
    typhonVm = callPackage ./vm.nix { buildJIT = false;
                                      libsodium = libsodium0; };
    typhonVmCrashy = callPackage ./vm.nix { buildJIT = true; };
    mast = callPackage ./mast.nix { typhonVm = typhonVm; };
    typhonDumpMAST = callPackage ./dump.nix {};
    # XXX broken for unknown reasons
    # bench = callPackage ./bench.nix { typhonVm = typhonVm; mast = mast; };
    mt = callPackage ./mt.nix { typhonVm = typhonVm; mast = mast; };
    mtLite = callPackage ./mt.nix { typhonVm = typhonVm; mast = mast; withBuild = false;};
    mtDocker = nixpkgs.dockerTools.buildImage {
        name = "monte";
        tag = "latest";
        contents = [mtLite typhonVm];
        config = {
            Cmd = [ "/bin/mt" "repl" ];
            WorkingDir = "/";
            };
        };
    };
in
  typhon
