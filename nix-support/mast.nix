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
  exts = [ ".mt" ".mt.md" ".asdl" ];
  # Compile a whole tree.
  buildMonteTree = root: context: files: lib.concatLists (lib.mapAttrsToList (filename: filetype:
    let
      rel = if context == "" then filename else context + ("/" + filename);
      abs = root + ("/" + rel);
    in if filetype == "directory"
      then buildMonteTree root rel (builtins.readDir abs)
      else let
        ext = lib.findFirst (ext: lib.hasSuffix ext filename) "none" exts;
        rename = n: (lib.removeSuffix ext n) + ".mast";
      in lib.optional (ext != "none") {
        name = rename rel;
        path = buildMonteModule (rename filename) abs;
      }
  ) files);
  tree = buildMonteTree mastSrc "" (builtins.readDir mastSrc);
  buildMASTFarm = pkgs.linkFarm "mast" tree;
in buildMASTFarm.overrideAttrs (attrs: {
  # Run the tests in the built tree using the built tree's loader.
  buildCommand = attrs.buildCommand + ''
    ${typhonVm}/mt-typhon -l $out $out/loader test all-tests
  '';
})
