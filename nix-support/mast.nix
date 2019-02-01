{stdenv, pkgs, lib, typhonVm}:
let
  boot = ../boot;
  # Don't preprocess the mast/ folder with lit.sh
  mastSrc = ../mast;
  # Compile a single module from .mt to .mast
  buildMonteModule = name: mt: let
    basename = baseNameOf mt;
    flags = if basename == "prelude.mt" || basename == "loader.mt"
      then "-noverify"
      else "";
    in pkgs.runCommand name {} ''
        ${typhonVm}/mt-typhon -l ${boot} ${boot}/loader run montec ${flags} ${mt} $out
      '';
  mtToMast = filename: (lib.removeSuffix ".mt" filename) + ".mast";
  # Compile a whole tree.
  buildMonteTree = root: context: files: lib.concatLists (lib.mapAttrsToList (filename: filetype:
    let
      rel = if context == "" then filename else context + ("/" + filename);
      abs = root + ("/" + rel);
    in if filetype == "directory"
      then buildMonteTree root rel (builtins.readDir abs)
      else if lib.hasSuffix ".mt" filename then [{
        name = mtToMast rel;
        path = buildMonteModule (mtToMast filename) abs;
      }] else []
  ) files);
  tree = buildMonteTree mastSrc "" (builtins.readDir mastSrc);
  buildMASTFarm = pkgs.linkFarm "mast" tree;
in buildMASTFarm.overrideAttrs (attrs: {
  # Run the tests in the built tree using the built tree's loader.
  buildCommand = attrs.buildCommand + ''
    ${typhonVm}/mt-typhon -l $out $out/loader test all-tests
  '';
})
