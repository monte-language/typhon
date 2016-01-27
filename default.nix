{ system ? builtins.currentSystem }:
let
  nixpkgs = import <nixpkgs> { inherit system; };
  lib = nixpkgs.lib;
  typhon = with nixpkgs; rec {
    typhonVm_O2 = callPackage ./nix/vm.nix { buildJIT = false; };
    typhonVm = callPackage ./nix/vm.nix { buildJIT = true; };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
    bench = callPackage ./nix/bench.nix { typhonVm = typhonVm; mast = mast; };

    montePackage = s @ { name, version, src, ... }: let
      mtSources = builtins.attrNames (builtins.readDir src);
      mastNames = map (builtins.replaceStrings [".mt"] [".mast"]) mtSources;
      montec = source: dest:
        "${typhonVm}/mt-typhon -l ${mast}/mast ${mast}/mast/montec -mix -format mast $src/${source} ${dest}";
      mastInstall = mast: "cp ${mast} $out/mast/";
      stuff = {
        name = "monte-${name}-${version}";
        buildInputs = [ typhonVm mast ];
        doCheck = false;
        buildPhase = lib.concatStringsSep "\n"
          (lib.zipListsWith montec mtSources mastNames);
        installPhase = ''
          mkdir -p $out/mast
          '' + lib.concatStringsSep "\n" (map mastInstall mastNames);
      };
    in
      nixpkgs.stdenv.mkDerivation (s // stuff);
  };
in
  typhon
