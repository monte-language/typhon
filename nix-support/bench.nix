{stdenv, lib, typhonVm, mast}:

stdenv.mkDerivation {
    name = "typhon-bench";
    buildInputs = [ typhonVm mast ];
    buildPhase = ''
      ln -s ${typhonVm}/bin/mt-typhon .
      ./mt-typhon -l ${mast} -l ${mast}/mast -b ${mast}/loader bench \
         ${mast}/mast/bench/{brot,nqueens,primeCount,richards}
      '';#*/
    installPhase = ''
      mkdir -p $out/nix-support/
      cp bench.html $out/
      echo "nix-build" >> $out/nix-support/hydra-build-products
      echo "channel" >> $out/nix-support/hydra-build-products
      echo "report benchmark $out/bench.html" >> $out/nix-support/hydra-build-products
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      let p = toString path;
       in ((lib.hasPrefix (loc "/mast/bench/") p &&
            (type == "directory" || lib.hasSuffix ".mt" p)) ||
        p == loc "/mast/benchRunner.mt")) ./..;
}
