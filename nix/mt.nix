{stdenv, lib, python27, typhonVm, mast, nix, nix-prefetch-scripts}:
let
  # I wanted to use builtins.toFile, but it doesn't work. Why? ~ C.
  mt-bake = ''
    ${python27}/bin/python $out/nix/mt-bake.py
    ${nix}/bin/nix-build -E "let pkgs = import <nixpkgs> {}; \
      lockSet = builtins.fromJSON (builtins.readFile ./mt-lock.json); \
      in pkgs.callPackage $out/nix/montePackage.nix { typhonVm = ${typhonVm}; mast = ${mast}; } lockSet"
  '';
in
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
      cp nix/montePackage.nix $out/nix
      cat <(echo "FETCHERS = {'git': '${nix-prefetch-scripts + "/bin/nix-prefetch-git"}'}")  nix/mt-bake.py.in > $out/nix/mt-bake.py
      echo "${typhonVm}/mt-typhon -l ${mast}/mast -l ${mast} ${mast}/loader run repl" > $out/bin/mt-repl
      chmod +x $out/bin/mt-repl

      cat > $out/bin/mt-bake <<EOF
      ${mt-bake}
      EOF
      chmod +x $out/bin/mt-bake
      '';
    src = let loc = part: (toString ./..) + part;
     in builtins.filterSource (path: type:
      (toString path) == loc "/default.nix" ||
      lib.hasPrefix (loc "/nix") (toString path)) ./..;
  }
