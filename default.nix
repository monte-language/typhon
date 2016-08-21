{ system ? builtins.currentSystem }:
let
  pkgs = import <nixpkgs> { inherit system; };
  lib = pkgs.lib;
  vmSrc = builtins.filterSource (path: type:
   let rel = lib.removePrefix (toString ./.) path;
   in (lib.hasPrefix "/typhon/" rel &&
       (type == "directory" || lib.hasSuffix ".py" rel)) ||
    rel == "/typhon" ||
    rel == "/main.py") ./.;
  mastSrc = builtins.filterSource (path: type:
   let rel = lib.removePrefix (toString ./.) path;
   in ((lib.hasPrefix "/mast/" rel &&
        (type == "directory" || lib.hasSuffix ".mt" rel)) ||
       (lib.hasPrefix "/boot/" rel &&
        (type == "directory" || lib.hasSuffix ".mast" rel)) ||
    rel == "/mast" ||
    rel == "/boot" ||
    rel == "/Makefile" ||
    rel == "/loader.mast" ||
    rel == "/repl.mast")) ./.;
in
pkgs.callPackage ./nix-support/typhon.nix { inherit vmSrc mastSrc system; }
