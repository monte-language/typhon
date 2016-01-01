{stdenv, lib, typhonVm}:

stdenv.mkDerivation {
    name = "typhon";
    buildInputs = [ typhonVm ];
    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      make mast bench fun repl.mast
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r mast repl.mast $out/
      echo "${typhonVm}/mt-typhon -l $out/mast $out/repl" > $out/bin/monte
      chmod +x $out/bin/monte
      '';
    checkPhase = "make testMast";
    doCheck = true;
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in ((lib.hasPrefix (loc "/mast/") p &&
            (type == "directory" || lib.hasSuffix ".mt" p)) ||
           (lib.hasPrefix (loc "/boot/") p &&
            (type == "directory" || lib.hasSuffix ".ty" p || lib.hasSuffix ".mast" p)) ||
        p == loc "/mast" ||
        p == loc "/boot" ||
        p == loc "/Makefile" ||
        p == loc "/repl.mast")) ./..;
}
