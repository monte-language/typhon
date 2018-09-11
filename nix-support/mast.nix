{stdenv, pkgs, lib, typhonVm, mastSrc}:

stdenv.mkDerivation {
    name = "typhon";

    src = mastSrc;

    buildInputs = [ typhonVm
      # Needed for lit.sh
      pkgs.gawk pkgs.less ];

    shellHook = ''
    function rrTest() {
       CNT=0
       ln -s ${typhonVm}/mt-typhon .
       while make testMast MT_TYPHON="${pkgs.rr}/bin/rr record ${typhonVm}/mt-typhon"; do
           make clean
           let CNT++
           echo $CNT
       done
       echo $CNT
    }
    '';

    # Make lit.sh call bash directly instead of invoking an inner nix-shell;
    # with Nix 2 the inner-shell trick doesn't work right.
    patchPhase = ''
      sed -i -e '1 s|^.*$|#!${pkgs.bash}/bin/bash|' lit.sh
    '';

    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      make
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp -r mast loader.mast $out/
    '';

    checkPhase = "make testMast";
    doCheck = true;
}
