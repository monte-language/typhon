{stdenv, lib, pypy, typhonVm, mast, nix, nix-prefetch-scripts}:

stdenv.mkDerivation {
    name = "mt";
    buildInputs = [ typhonVm mast nix-prefetch-scripts ];
    buildPhase = ''
      '';
    installPhase = ''
      mkdir -p $out/bin
      cp -r default.nix nix/ $out
      echo "${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} loader run repl" > $out/bin/mt-repl
      echo "${pypy}/bin/pypy $out/nix/mt-bake.py; ${nix}/bin/nix-build -E \"let pkgs = import <nixpkgs> {}; in pkgs.callPackage \$PWD/default.nix { typhonVm = ${typhonVm}; mast = ${mast}; }\"" > $out/bin/mt-bake
      chmod +x $out/bin/mt-repl
      chmod +x $out/bin/mt-bake
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      (toString path) == loc "/default.nix" ||
      lib.hasPrefix (loc "/nix") (toString path)) ./..;
}
