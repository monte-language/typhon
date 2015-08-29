let
  pkgs = import <nixpkgs> { };
  jobs = rec {
  typhonVm = import ./nix/vm.nix {
    inherit (pkgs) stdenv lib fetchFromBitbucket pypy pypyPackages;};
  mast = import ./nix/mast.nix {
    inherit typhonVm;
    inherit (pkgs) stdenv lib;};
  mastWithTests = pkgs.lib.overrideDerivation mast (oldAttrs: {
    inherit mast;
    doCheck = true;});
  };
in
  jobs
