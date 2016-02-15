{stdenv, lib, pypy, typhonVm, mast, nix, nix-prefetch-scripts}:

stdenv.mkDerivation {
    name = "mt";
    buildInputs = [ typhonVm mast nix-prefetch-scripts ];
    buildPhase = ''
      '';
    installPhase = ''
      mkdir -p $out/bin
      mkdir -p $out/nix
      cp default.nix $out
      cp nix/mt.nix $out/nix
      cp nix/mt-instantiate.py $out/nix
      cat <(echo "FETCHERS = {'git': '${nix-prefetch-scripts + "/bin/nix-prefetch-git"}'}")  nix/mt-bake.py.in > $out/nix/mt-bake.py
      echo "${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} loader run repl" > $out/bin/mt-repl
      echo "${pypy}/bin/pypy $out/nix/mt-bake.py; ${pypy}/bin/pypy $out/nix/mt-instantiate.py; ${nix}/bin/nix-build -E \"let pkgs = import <nixpkgs> {}; in pkgs.callPackage \$PWD/default.nix { typhonVm = ${typhonVm}; mast = ${mast}; }\"" > $out/bin/mt-bake
      chmod +x $out/bin/mt-repl
      chmod +x $out/bin/mt-bake
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      (toString path) == loc "/default.nix" ||
      lib.hasPrefix (loc "/nix") (toString path)) ./..;
}
