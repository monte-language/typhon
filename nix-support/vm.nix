{ stdenv, fetchFromGitLab, fetchFromGitHub, libsodium, libuv, libffi,
pypy, system, vmSrc, rpypkgs, buildJIT }:

let
  # https://foss.heptapod.net/pypy/pypy/
  pypySrc = fetchFromGitLab {
    domain = "foss.heptapod.net";
    owner = "pypy";
    repo = "pypy";
    # release candidate from branch release-pypy3.8-v7.x
    rev = "90fd9ed34d52181de59cbfff863719472b05418e";
    sha256 = "03cshgvh8qcsyac4q4vf0sbvcm1m2ikgwycwip4cc7sw9pzpw6a3";
  };
in rpypkgs.lib.${system}.mkRPythonDerivation {
  entrypoint = "main.py";
  binName = "mt-typhon";
  withLibs = ls: [ ls.macropy ];
  optLevel = if buildJIT then "jit" else "2";
} {
  name = if buildJIT then "typhon-vm" else "typhon-vm-nojit";

  src = vmSrc;

  buildInputs = [ libuv libsodium ];
  propagatedBuildInputs = [ libffi libuv libsodium ];

  shellHook = ''
    export TYPHON_LIBRARY_PATH=${libuv.out}/lib:${libsodium.out}/lib
    export PYTHONPATH=$TMP/typhon:$PYTHONPATH
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

  separateDebugInfo = true;
}
