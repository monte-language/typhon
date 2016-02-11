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
    mtBake = {pkgFile}: callPackage pkgFile {typhonVm = typhonVm; mast = mast; };
    montePackage = s @ { name, version, src, entrypoints, ... }: let
      mtSources = builtins.attrNames (builtins.readDir src);
      mastNames = map (builtins.replaceStrings [".mt"] [".mast"]) mtSources;
      montec = source: dest:
        "${typhonVm}/mt-typhon -l ${mast}/mast ${mast}/loader run ${mast}/mast/montec -mix $src/${source} ${dest}";
      mastInstall = mast: "cp ${mast} $out/mast/";
      mastEntrypoint = exe: ''
        echo "${typhonVm}/mt-typhon -l ${mast}/mast ${mast}/loader run $out/mast/${exe} \"\$@\"" > $out/bin/${exe}
        chmod +x $out/bin/${exe}
        '';
      stuff = {
        name = "monte-${name}-${version}";
        buildInputs = [ typhonVm mast ];
        doCheck = false;
        buildPhase = lib.concatStringsSep "\n"
          (lib.zipListsWith montec mtSources mastNames);
        installPhase = ''
          mkdir -p $out/mast
          mkdir -p $out/bin
          '' + lib.concatStringsSep "\n" (map mastInstall mastNames) + "\n"
          + lib.concatStringsSep "\n" (map mastEntrypoint entrypoints);
      };
    in
      nixpkgs.stdenv.mkDerivation (s // stuff);
  };
in
  typhon
