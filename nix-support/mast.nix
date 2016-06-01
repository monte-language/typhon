{stdenv, lib, typhonVm, mastSrc}:

stdenv.mkDerivation {
    name = "typhon";
    buildInputs = [ typhonVm ];
    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      make mast bench fun repl.mast
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r mast loader.mast $out/
      cp -r mast repl.mast $out/
      '';
    checkPhase = "make testMast";
    doCheck = true;
    src = mastSrc;
}
