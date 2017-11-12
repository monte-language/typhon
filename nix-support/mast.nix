{stdenv, pkgs, lib, typhonVm, mastSrc}:

stdenv.mkDerivation {
    name = "typhon";
    buildInputs = [ typhonVm ];
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
    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r mast loader.mast $out/
      '';
    checkPhase = "make testMast";
    doCheck = true;
    src = mastSrc;
}
