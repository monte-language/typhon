{stdenv, lib, typhonVm}:

stdenv.mkDerivation {
    name = "typhon";
    buildInputs = [ typhonVm ];
    buildPhase = ''
      ln -s ${typhonVm}/mt-typhon .
      make mast fun repl.ty
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r mast repl.ty $out/
      echo "${typhonVm}/mt-typhon -l $out/mast $out/repl.ty" > $out/bin/monte
      chmod +x $out/bin/monte
      '';
    checkPhase = "make testMast";
    doCheck = false;
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in ((lib.hasPrefix (loc "/mast/") p &&
            (type == "directory" || lib.hasSuffix ".mt" p)) ||
           (lib.hasPrefix (loc "/boot/") p &&
            (type == "directory" || lib.hasSuffix ".ty" p)) ||
        p == loc "/mast" ||
        p == loc "/boot" ||
        p == loc "/Makefile" ||
        p == loc "/repl.mt")) ./..;
}
