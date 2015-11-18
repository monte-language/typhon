{stdenv, fetchFromBitbucket, lib, libsodium, libuv, libffi, pkgconfig, pypy, pypyPackages, buildJIT}:

# $ nix-prefetch-hg https://bitbucket.org/pypy/pypy
let pypySrc = fetchFromBitbucket {
    owner = "pypy";
    repo = "pypy";
    rev = "5f8302b8bf9f";
    sha256 = "19ql1brvn0vmhcx9rax6csikmf3irmb1b7bi1qprdydx5ylp28rp";
  };
  optLevel = if buildJIT then "-Ojit" else "-O2";
in
stdenv.mkDerivation {
  name = "typhon-vm";
  buildInputs = [ pypy pypyPackages.pytest pypyPackages.twisted pypySrc
                  pkgconfig libffi libuv libsodium ];
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
