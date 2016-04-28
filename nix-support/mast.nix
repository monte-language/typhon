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
      echo "${typhonVm}/mt-typhon -l $out/mast -l $out loader run repl" > $out/bin/monte
      chmod +x $out/bin/monte
      '';
    checkPhase = "make testMast";
    doCheck = true;
    src = mastSrc;
}
