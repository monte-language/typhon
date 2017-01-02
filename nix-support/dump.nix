{stdenv, fetchzip, lib, libuv, libffi, pkgconfig, python27, python27Packages,
 afl}:

# $ nix-prefetch-hg https://bitbucket.org/pypy/pypy
let
  pypySrc = fetchzip {
    url = "https://bitbucket.org/pypy/pypy/downloads/pypy2-v5.4.1-src.tar.bz2";
    sha256 = "0ch7whwy2b7dva1fasvq0h914ky56y3aam6ky3nb9qxnd5gxji6h";
  };
in
stdenv.mkDerivation {
  name = "typhon-dump-mast";
  buildInputs = [ python27 python27Packages.pytest python27Packages.twisted pypySrc
                  pkgconfig libffi afl ];
  buildPhase = ''
    source $stdenv/setup
    mkdir -p ./rpython/_cache
    cp -r ${pypySrc}/rpython .
    cp -r $src/dump.py .
    # CC=afl-gcc python -mrpython -O2 dump.py
    python -mrpython -O2 dump.py
    '';
  doCheck = false;
  installPhase = ''
    mkdir -p $out/bin/
    cp mt-dump-mast $out/bin/
    '';
  dontStrip = true;
  src = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/dump.py") ./..;
}
