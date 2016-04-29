{stdenv, fetchzip, lib, libuv, libffi, pkgconfig, python27, python27Packages,
 afl}:

# $ nix-prefetch-hg https://bitbucket.org/pypy/pypy
let pypySrc = fetchzip {
    url = "https://bitbucket.org/pypy/pypy/downloads/pypy-5.0.0-src.tar.bz2";
    sha256 = "1hxjhm66081hnhdkf0fifswc9js9qi88zyy7pfpcwlxl029sddj0";
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
    CC=afl-gcc python -mrpython -O2 dump.py
    '';
  doCheck = false;
  installPhase = ''
    mkdir $out
    cp mt-dump-mast $out/
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
