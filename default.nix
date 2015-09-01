let
  nixpkgs = import <nixpkgs> { };
  jobs = with nixpkgs; rec {
    typhonVm = callPackage ./nix/vm.nix { };
    mast = callPackage ./nix/mast.nix { typhonVm = typhonVm; };
    mastWithTests = pkgs.lib.overrideDerivation mast (oldAttrs: {
      inherit mast;
      doCheck = true;});
  };
in
  jobs
