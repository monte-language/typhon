{stdenv, fetchFromBitbucket, lib, libuv, libffi, pkgconfig, pypy, pypyPackages, buildJIT}:

let pypySrc = fetchFromBitbucket {
    owner = "pypy";
    repo = "pypy";
    rev = "5345333d8dcd";
    sha256 = "0qsxjql2x7qkmg20mzjp2b02fds5vai1jr5asbwvg5yp3qqnmdwk";
  };
  optLevel = if buildJIT then "-Ojit" else "-O2";
in
stdenv.mkDerivation {
  name = "typhon-vm";
  buildInputs = [ pypy pypyPackages.pytest pypyPackages.twisted pypySrc
                  pkgconfig libffi libuv ];
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
  fixupPhase = ''
    patchelf --shrink-rpath $out/mt-typhon
    strip $out/mt-typhon
    '';
  src = let loc = part: (toString ./..) + part;
   in builtins.filterSource (path: type:
    let p = toString path;
     in (lib.hasPrefix (loc "/typhon/") p &&
         (type == "directory" || lib.hasSuffix ".py" p)) ||
      p == loc "/typhon" ||
      p == loc "/main.py") ./..;
}
