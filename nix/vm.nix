{stdenv, fetchzip, lib, libsodium, libuv, libffi, pkgconfig, pypy, pypyPackages, buildJIT}:

# $ nix-prefetch-hg https://bitbucket.org/pypy/pypy
let pypySrc = fetchzip {
    url = "https://bitbucket.org/pypy/pypy/downloads/pypy-4.0.1-src.tar.bz2";
    sha256 = "0saq5qd18wnqx9piyqcc3c23qbdnwbw8gxab5yyqpd0c44xymxw2";
  };
  optLevel = if buildJIT then "-Ojit" else "-O2";
in
stdenv.mkDerivation {
  name = "typhon-vm";
  buildInputs = [ pypy pypyPackages.pytest pypyPackages.twisted pypySrc
                  pkgconfig libffi libuv libsodium ];
  shellHook = ''
    export TYPHON_LIBRARY_PATH=${libuv}/lib:${libsodium}/lib
    export PYTHONPATH=$TMP/typhon
    if [ -e $TMP/typhon ]; then
        rm -rf $TMP/typhon
    fi
    mkdir -p $TMP/typhon/rpython/_cache
    # Ridiculous, but necessary.
    cp -r ${pypySrc}/* $TMP/typhon
    chmod -R 755 $TMP/typhon
    typhon_cleanup () {
        rm -rf $TMP/typhon
    }
    trap typhon_cleanup EXIT
  '';
  buildPhase = ''
    source $stdenv/setup
    mkdir -p ./rpython/_cache
    cp -r ${pypySrc}/rpython .
    cp -r $src/main.py .
    pypy -mrpython ${optLevel} main.py
    '';
  doCheck = true;
  checkPhase = "trial typhon.test";
  installPhase = ''
    mkdir $out
    cp mt-typhon $out/
    '';
  dontStrip = true;
  fixupPhase = ''
    patchelf --shrink-rpath $out/mt-typhon
    '';
  src = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/main.py") ./..;
}
