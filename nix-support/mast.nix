{stdenv, pkgs, lib, typhonVm}:
let
  boot = ../boot;
  mastSrc = ../mast;
  buildMonteModule = name: mt: let
    basename = baseNameOf mt;
    flags = if basename == "prelude.mt" || basename == "loader.mt"
      then "-noverify"
      else "";
  in pkgs.runCommand name {} ''
      ${typhonVm}/mt-typhon -l ${boot} ${boot}/loader run montec ${flags} ${mt} $out
    '';
  mtToMast = filename: (lib.removeSuffix ".mt" filename) + ".mast";
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
in buildMASTFarm
  # in stdenv.mkDerivation {
  #     name = "typhon";
  # 
  #     src = mastSrc;
  # 
  #     buildInputs = [ typhonVm
  #       # Needed for lit.sh
  #       pkgs.gawk pkgs.less ];
  # 
  #     shellHook = ''
  #     function rrTest() {
  #        CNT=0
  #        ln -s ${typhonVm}/mt-typhon .
  #        while make testMast MT_TYPHON="${pkgs.rr}/bin/rr record ${typhonVm}/mt-typhon"; do
  #            make clean
  #            let CNT++
  #            echo $CNT
  #        done
  #        echo $CNT
  #     }
  #     '';
  # 
  #     # Make lit.sh call bash directly instead of invoking an inner nix-shell;
  #     # with Nix 2 the inner-shell trick doesn't work right.
  #     patchPhase = ''
  #       sed -i -e '1 s|^.*$|#!${pkgs.bash}/bin/bash|' lit.sh
  #     '';
  # 
  #     buildPhase = ''
  #       ln -s ${typhonVm}/mt-typhon .
  #       make
  #     '';
  # 
  #     installPhase = ''
  #       mkdir -p $out/bin
  #       cp -r mast loader.mast $out/
  #     '';
  # 
  #     checkPhase = "make testMast";
  #     doCheck = true;
  # }
